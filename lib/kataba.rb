require 'nokogiri'
require 'tmpdir'
require 'digest/md5'
require 'open-uri'

module Kataba

  class << self
    attr_accessor :configuration
  end

  def self.configure
    yield(configuration) if block_given?
  end

  def self.configuration
    @configuration ||=  Configuration.new
  end

  class Configuration
    attr_accessor :offline_storage

    def initialize
      @offline_storage = "#{Dir.tmpdir}/kataba"
    end
  end

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
          file.write(open(xsd_uri).read)
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
