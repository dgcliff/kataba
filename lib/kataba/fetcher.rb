require 'net/http'
require 'uri'

module Kataba
  # Fetches a schema body, recovering from LoC-shaped delivery quirks
  # that a verbatim URI.open would surface as cache-poisoning errors:
  #
  #   - 5xx (Cloudflare bot-management 503/529, origin overload):
  #     retry once on the alternate scheme.
  #   - same-origin HTTPS->HTTP 3xx: follow. open-uri refuses all
  #     scheme downgrades; we relax to same-origin because the
  #     consumer already trusted this host by putting it in their
  #     schemaLocation. Cross-origin downgrades stay refused — that's
  #     the actual DNS-redirect attack vector.
  #   - /mods/xml.xsd vanity path: rewrite to /standards/mods/xml.xsd
  #     before the first request. LoC publishes the file only at the
  #     canonical /standards path; the vanity path redirects HTTPS->HTTP
  #     and 503s. Applied here so transitive xs:import resolution from
  #     mods-3-N.xsd benefits, not just top-level fetch_schema calls.
  #
  # mirror_list remains the consumer's backstop for URI-identity
  # changes (path renames, host moves) that no delivery heuristic
  # can rescue.
  class Fetcher
    MAX_REDIRECTS = 5

    # LoC publishes xml.xsd only at /standards/mods/xml.xsd; the /mods/xml.xsd
    # path used in every mods-3-N.xsd xs:import 503s after a scheme bounce.
    VANITY_PATH_REWRITES = {
      '/mods/xml.xsd' => '/standards/mods/xml.xsd',
    }.freeze

    class FetchError < StandardError; end

    def initialize(uri)
      @original_uri = uri
    end

    def fetch
      attempt(normalize(@original_uri), alt_scheme_retry: true)
    end

    private

    def normalize(uri)
      VANITY_PATH_REWRITES.each do |from, to|
        rewritten = uri.sub(%r{(\Ahttps?://[^/]+)#{Regexp.escape(from)}\z}i, "\\1#{to}")
        return rewritten unless rewritten == uri
      end
      uri
    end

    def attempt(uri, alt_scheme_retry:)
      response = request_with_redirects(uri, redirect_depth: 0)

      case response
      when Net::HTTPSuccess
        response.body
      when Net::HTTPServerError
        if alt_scheme_retry && (alt = swap_scheme(uri))
          attempt(alt, alt_scheme_retry: false)
        else
          raise FetchError, "#{response.code} #{response.message} fetching #{uri}"
        end
      else
        raise FetchError, "#{response.code} #{response.message} fetching #{uri}"
      end
    end

    def request_with_redirects(uri, redirect_depth:)
      raise FetchError, "too many redirects fetching #{@original_uri}" if redirect_depth > MAX_REDIRECTS

      parsed = URI.parse(uri)
      http = Net::HTTP.new(parsed.host, parsed.port)
      http.use_ssl = (parsed.scheme == 'https')
      response = http.get(parsed.request_uri)

      if response.is_a?(Net::HTTPRedirection)
        target = resolve_redirect(parsed, response['location'])
        request_with_redirects(target, redirect_depth: redirect_depth + 1)
      else
        response
      end
    end

    def resolve_redirect(from, location)
      raise FetchError, "redirect with no Location header from #{from}" if location.nil? || location.empty?

      target = URI.parse(location)
      target = from + target if target.relative?

      if from.scheme == 'https' && target.scheme == 'http' && from.host != target.host
        raise FetchError, "cross-origin HTTPS->HTTP redirect refused: #{from} -> #{target}"
      end

      target.to_s
    end

    def swap_scheme(uri)
      if uri.start_with?('https://')
        uri.sub(/\Ahttps:/, 'http:')
      elsif uri.start_with?('http://')
        uri.sub(/\Ahttp:/, 'https:')
      end
    end
  end
end
