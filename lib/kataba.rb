require 'nokogiri'
require 'tmpdir'
require 'digest/md5'
require 'open-uri'

module Kataba

  class << self
    # Simple attribute for configuration
    attr_accessor :configuration
  end

  # Allows for configuration by block
  #
  # Example:
  #  MegaLotto.configure do |config|
  #   config.drawing_count = 10
  #  end

  def self.configure
    yield(configuration) if block_given?
  end

  def self.configuration
    @configuration ||=  Configuration.new
  end

  # Undoes any configuration - this method was built for testing purposes
  #
  # Example:
  #   Kataba.reset

  def self.reset
    @configuration = Configuration.new
  end

  class Configuration
    # Offline storage is "#{Dir.tmpdir}/kataba" by default.
    # This attribute allows the user to change that default value.
    #
    # Example:
    #   Kataba.configuration.offline_storage = "/tmp/kataba"
    attr_accessor :offline_storage
    # The user can optionally provide a mirror list to reduce stress on primary XSD providers.
    # This attribute allows the user to configure Kataba to use a YAML file with key/value pairs of
    # original/mirror values. Sample YAML file can be found at https://github.com/dgcliff/kataba/blob/master/test/fixtures/mirror.yml
    #
    # Example:
    #   Kataba.configuration.mirror_list = File.join(Rails.root, 'config', 'mirror.yml')
    attr_accessor :mirror_list

    # Default configuration values
    def initialize
      @offline_storage = "#{Dir.tmpdir}/kataba"
    end
  end

  # If already downloaded, uses offline version. If not, downloads from the URI provided.
  # If mirror list is configured, searches for mirrored URI instead.
  #
  # Example:
  #   Kataba.fetch_schema("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd")
  #
  # Arguments:
  #   xsd_uri: (String)

  def self.fetch_schema(xsd_uri)
    uri_md5 = Digest::MD5.hexdigest(xsd_uri)
    dir_path = "#{self.configuration.offline_storage}"
    xsd_path = "#{dir_path}/#{uri_md5}.xsd"

    # Does the offline version exist already?
    if !(File.exists?(xsd_path))
      # If not, go download
      xsd_array = []
      xsd_array << xsd_uri
      download_xsd(xsd_array)
    end

    # Validate and return Nokogiri schema
    Dir.chdir(dir_path) do
      return Nokogiri::XML::Schema(IO.read(xsd_path))
    end
  end

  private

    def self.download_xsd(xsd_uri_array)
      new_xsd_uris = []
      file_paths = []

      # Download files
      xsd_uri_array.each do |xsd_uri|
        uri_md5 = Digest::MD5.hexdigest(xsd_uri)

        dir_name = "#{self.configuration.offline_storage}"

        # Make dir if needed
        unless File.directory?(dir_name)
          FileUtils.mkdir_p(dir_name)
        end

        file_path = "#{dir_name}/#{uri_md5}.xsd"

        file_paths << file_path

        open(file_path, "wb+") do |file|
          if !self.configuration.mirror_list.to_s.empty?
            mirror_list = YAML.load_file(self.configuration.mirror_list)
            mirror = mirror_list[xsd_uri]
            if mirror.to_s.empty?
              # No mirror for that uri
              file.write(open(xsd_uri).read)
            else
              file.write(open(mirror).read)
            end
          else
            file.write(open(xsd_uri).read)
          end
        end
      end

      # Search inside for other schemaLocations
      file_paths.each do |file_path|
        new_xsd_uris = find_schemas(file_path)
      end

      if !new_xsd_uris.reject(&:empty?).empty?
        download_xsd(new_xsd_uris)
      end
    end

    def self.find_schemas(xml_file_path)
      xsd_uri_array = []

      # Open XML file
      doc = File.open(xml_file_path) { |f| Nokogiri::XML(f) }
      # search for schemaLocations
      doc.xpath("//@schemaLocation").each do |node|
        if !node.value.to_s.empty?
          # Add to array
          xsd_uri_array << node.value
          # Get MD5
          uri_md5 = Digest::MD5.hexdigest(node.value)
          # Reassign attribute value
          node.value = "#{uri_md5}.xsd"
        end
      end

      # Overwrite with md5'd doc
      File.write(xml_file_path, doc.to_xml)

      return xsd_uri_array
    end
end
