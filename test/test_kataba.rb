require 'minitest/autorun'
require 'webmock/minitest'
require 'kataba'
require 'fileutils'
require 'yaml'
require 'nokogiri'

class KatabaTest < Minitest::Test
  FIXTURE_DIR = File.expand_path('fixtures', __dir__)

  MODS_URI  = "http://www.loc.gov/standards/mods/v3/mods-3-5.xsd"
  XLINK_URI = "http://www.loc.gov/standards/xlink/xlink.xsd"
  # XML_URI is the path embedded in every mods-3-N.xsd's xs:import.
  # XML_REWRITTEN_URI is where LoC actually serves the file today; the
  # Fetcher rewrites embedded -> rewritten before issuing any request.
  XML_URI           = "http://www.loc.gov/mods/xml.xsd"
  XML_REWRITTEN_URI = "http://www.loc.gov/standards/mods/xml.xsd"

  MIRROR_MODS  = "https://raw.githubusercontent.com/dgcliff/kataba/master/test/fixtures/mods-3-5.xsd"
  MIRROR_XLINK = "https://raw.githubusercontent.com/dgcliff/kataba/master/test/fixtures/xlink.xsd"
  MIRROR_XML   = "https://raw.githubusercontent.com/dgcliff/kataba/master/test/fixtures/xml.xsd"

  BAD_MIRROR = "https://www.google.com/broken"

  def setup
    FileUtils.rm_rf(Kataba.configuration.offline_storage)
    # Reset so each test gets clean assert_(not_)requested counts.
    WebMock.reset!

    # Stub the LoC URLs the Fetcher will actually request when no mirror
    # is configured. xml.xsd is stubbed at the /standards path because
    # the Fetcher rewrites /mods/xml.xsd before issuing the request.
    stub_request(:get, MODS_URI).to_return(status: 200, body: File.read("#{FIXTURE_DIR}/mods-3-5.xsd"))
    stub_request(:get, XLINK_URI).to_return(status: 200, body: File.read("#{FIXTURE_DIR}/xlink.xsd"))
    stub_request(:get, XML_REWRITTEN_URI).to_return(status: 200, body: File.read("#{FIXTURE_DIR}/xml.xsd"))

    # Stub mirror URLs (used when mirror_list is configured)
    stub_request(:get, MIRROR_MODS).to_return(status: 200, body: File.read("#{FIXTURE_DIR}/mods-3-5.xsd"))
    stub_request(:get, MIRROR_XLINK).to_return(status: 200, body: File.read("#{FIXTURE_DIR}/xlink.xsd"))
    stub_request(:get, MIRROR_XML).to_return(status: 200, body: File.read("#{FIXTURE_DIR}/xml.xsd"))

    # Stub the deliberately-broken URL in bad_mirror.yml
    stub_request(:get, BAD_MIRROR).to_return(status: 404)
  end

  def teardown
    FileUtils.rm_rf(Kataba.configuration.offline_storage)
    Kataba.reset
  end

  def test_xsd_return
    assert_kind_of Nokogiri::XML::Schema,
      Kataba.fetch_schema(MODS_URI)
  end

  def test_custom_directory
    full_path = "#{Dir.pwd}/xsd_files"
    Kataba.configuration.offline_storage = full_path
    Kataba.fetch_schema(MODS_URI)
    assert File.file?(full_path + "/01490ebdea13c1bc82a17e4783daeeaa.xsd")
    assert File.file?(full_path + "/534d7d1e9b53ece0bf0f5874444d8bcb.xsd")
    assert File.file?(full_path + "/c547c5ba5338defc42b59e2904542d30.xsd")
    FileUtils.rm_rf(full_path)
  end

  def test_default_directory
    assert Dir.exist?(File.expand_path("..", Kataba.configuration.offline_storage))
  end

  def test_mirror_list
    mirror_list = YAML.load_file(Dir.pwd + '/test/fixtures/mirror.yml')
    assert_equal MIRROR_MODS, mirror_list[MODS_URI]

    Kataba.configuration.mirror_list = Dir.pwd + '/test/fixtures/mirror.yml'

    assert_kind_of Nokogiri::XML::Schema,
      Kataba.fetch_schema(MODS_URI)

    # The mirror was actually used; the canonical URL was not
    assert_requested :get, MIRROR_MODS
    assert_not_requested :get, MODS_URI
  end

  # Regression: a mirror_list YAML with only comments (or otherwise empty)
  # loads as nil. The loader must treat that as "no mirror configured" and
  # fall through to the canonical URL, not NoMethodError on nil[xsd_uri].
  def test_empty_mirror_list_falls_through_to_canonical
    Kataba.configuration.mirror_list = "#{FIXTURE_DIR}/empty_mirror.yml"

    assert_kind_of Nokogiri::XML::Schema, Kataba.fetch_schema(MODS_URI)
    assert_requested :get, MODS_URI
  end

  def test_bad_mirror_list
    mirror_list = YAML.load_file(Dir.pwd + '/test/fixtures/bad_mirror.yml')
    assert_equal BAD_MIRROR, mirror_list[MODS_URI]

    Kataba.configuration.mirror_list = Dir.pwd + '/test/fixtures/bad_mirror.yml'

    assert_raises(Kataba::Fetcher::FetchError) { Kataba.fetch_schema(MODS_URI) }
  end

  # Regression: a malformed response (HTML error page, truncated stream,
  # garbage proxy stub) must not land at the canonical cache path. Without
  # the temp-write + parse-check, the bad bytes would poison the cache and
  # every subsequent fetch_schema would re-explode on the same content.
  def test_malformed_response_does_not_poison_cache
    bad_url = "http://example.com/malformed.xsd"
    stub_request(:get, bad_url).to_return(status: 200, body: "this is not xml at all")

    assert_raises(Nokogiri::XML::SyntaxError) { Kataba.fetch_schema(bad_url) }

    md5 = Digest::MD5.hexdigest(bad_url)
    storage = Kataba.configuration.offline_storage
    refute File.exist?("#{storage}/#{md5}.xsd"),     "final cache file should not exist after a malformed fetch"
    refute File.exist?("#{storage}/#{md5}.xsd.part"), ".part file should be cleaned up after a malformed fetch"
  end

  # Regression: if a cached XSD is somehow already corrupt on disk (e.g. a
  # pre-fix install that wrote one before this guard existed), fetch_schema
  # should evict it and refetch once rather than failing in perpetuity.
  def test_self_heals_pre_existing_malformed_cache
    storage = Kataba.configuration.offline_storage
    FileUtils.mkdir_p(storage)
    md5 = Digest::MD5.hexdigest(MODS_URI)
    poisoned_path = "#{storage}/#{md5}.xsd"
    File.write(poisoned_path, "this is not xml at all")

    assert_kind_of Nokogiri::XML::Schema, Kataba.fetch_schema(MODS_URI)
    # The healed cache parses cleanly now
    Nokogiri::XML(File.read(poisoned_path)) { |c| c.strict }
  end

  # Minimal XSD body for fetcher tests — valid XML, valid XSD, no nested
  # schemaLocations (so download_xsd doesn't recurse).
  MINIMAL_XSD = <<~XSD
    <?xml version="1.0"?>
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="root" type="xs:string"/>
    </xs:schema>
  XSD

  # Row 1 of the deployment-quirk table: HTTP 503 (Cloudflare bot
  # management), HTTPS 200. The fetcher retries on the alternate scheme.
  def test_fetcher_retries_on_alt_scheme_after_5xx
    http_url  = "http://example.com/mods.xsd"
    https_url = "https://example.com/mods.xsd"

    stub_request(:get, http_url).to_return(status: 503)
    stub_request(:get, https_url).to_return(status: 200, body: MINIMAL_XSD)

    assert_kind_of Nokogiri::XML::Schema, Kataba.fetch_schema(http_url)
    assert_requested :get, http_url
    assert_requested :get, https_url
  end

  # Row 2: a same-origin HTTPS->HTTP 301 (the redirect shape the xml.xsd
  # path used to bounce through). open-uri refuses this with RuntimeError;
  # the fetcher follows it because the consumer's trust is in the origin
  # and this is the origin's own call.
  def test_fetcher_follows_same_origin_https_to_http_redirect
    https_url = "https://example.com/xml.xsd"
    http_url  = "http://example.com/xml.xsd"

    stub_request(:get, https_url).to_return(status: 301, headers: { "Location" => http_url })
    stub_request(:get, http_url).to_return(status: 200, body: MINIMAL_XSD)

    assert_kind_of Nokogiri::XML::Schema, Kataba.fetch_schema(https_url)
    assert_requested :get, https_url
    assert_requested :get, http_url
  end

  # Cross-origin HTTPS->HTTP redirect is the actual downgrade-attack
  # vector (DNS-controlled redirect to attacker plaintext). Fetcher
  # refuses BEFORE issuing the downgraded request.
  def test_fetcher_refuses_cross_origin_https_to_http_redirect
    https_url = "https://a.example.com/x.xsd"
    evil_url  = "http://b.example.com/x.xsd"

    stub_request(:get, https_url).to_return(status: 301, headers: { "Location" => evil_url })

    assert_raises(Kataba::Fetcher::FetchError) { Kataba.fetch_schema(https_url) }
    assert_not_requested :get, evil_url
  end

  # A redirect loop must terminate. MAX_REDIRECTS = 5; a self-redirect
  # exhausts the cap and raises rather than running forever.
  def test_fetcher_caps_redirect_chain
    url = "https://example.com/loop.xsd"
    stub_request(:get, url).to_return(status: 301, headers: { "Location" => url })

    assert_raises(Kataba::Fetcher::FetchError) { Kataba.fetch_schema(url) }
  end

  # Happy path: a clean 200 doesn't trigger any speculative alt-scheme
  # retry. The original was fine; don't waste round trips.
  def test_fetcher_no_speculative_retry_on_success
    url     = "https://example.com/clean.xsd"
    alt_url = "http://example.com/clean.xsd"

    stub_request(:get, url).to_return(status: 200, body: MINIMAL_XSD)

    Kataba.fetch_schema(url)

    assert_requested :get, url, times: 1
    assert_not_requested :get, alt_url
  end

  # /mods/xml.xsd rewrite: every mods-3-N.xsd does an xs:import of
  # http://www.loc.gov/mods/xml.xsd, but LoC only serves the file from
  # /standards/mods/xml.xsd today — the embedded path redirects
  # HTTPS->HTTP and 503s. The Fetcher rewrites the path before any
  # request, so transitive import resolution actually reaches the file.
  def test_fetcher_rewrites_loc_mods_xml_path
    embedded_url  = "http://www.loc.gov/mods/xml.xsd"
    rewritten_url = "http://www.loc.gov/standards/mods/xml.xsd"

    stub_request(:get, rewritten_url).to_return(status: 200, body: MINIMAL_XSD)

    assert_kind_of Nokogiri::XML::Schema, Kataba.fetch_schema(embedded_url)
    assert_requested :get, rewritten_url
    assert_not_requested :get, embedded_url
  end

  # The rewrite is path-keyed, not host-keyed: any URI whose path is
  # exactly /mods/xml.xsd gets rewritten. Hosts that happen to share the
  # path inherit the redirect — in practice only LoC ships schemas with
  # this import.
  def test_fetcher_rewrite_is_path_keyed_not_loc_specific
    embedded_url  = "http://example.com/mods/xml.xsd"
    rewritten_url = "http://example.com/standards/mods/xml.xsd"

    stub_request(:get, rewritten_url).to_return(status: 200, body: MINIMAL_XSD)

    Kataba.fetch_schema(embedded_url)
    assert_requested :get, rewritten_url
    assert_not_requested :get, embedded_url
  end

  # The rewrite must NOT fire on unrelated paths that just happen to
  # contain "xml.xsd". A schemaLocation like .../something/xml.xsd
  # (anywhere but the literal /mods/xml.xsd path) is fetched verbatim.
  def test_fetcher_does_not_rewrite_unrelated_xml_xsd_paths
    url = "http://example.com/schemas/xml.xsd"
    stub_request(:get, url).to_return(status: 200, body: MINIMAL_XSD)

    Kataba.fetch_schema(url)
    assert_requested :get, url
  end

  # Regression: when the network fetch raises (vs. returns malformed
  # bytes), the cache directory must not be left with an orphaned 0-byte
  # .part file. With the fetch-before-open refactor, the .part is never
  # created on fetch failure.
  def test_no_orphaned_part_file_on_fetch_error
    http_url  = "http://example.com/dead.xsd"
    https_url = "https://example.com/dead.xsd"

    stub_request(:get, http_url).to_return(status: 503)
    stub_request(:get, https_url).to_return(status: 503)

    assert_raises(Kataba::Fetcher::FetchError) { Kataba.fetch_schema(http_url) }

    md5 = Digest::MD5.hexdigest(http_url)
    storage = Kataba.configuration.offline_storage
    refute File.exist?("#{storage}/#{md5}.xsd"),      "final cache file should not exist after fetch failure"
    refute File.exist?("#{storage}/#{md5}.xsd.part"), ".part file should not be orphaned after fetch failure"
  end
end
