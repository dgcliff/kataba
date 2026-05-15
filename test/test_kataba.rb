require 'minitest/autorun'
require 'webmock/minitest'
require 'kataba'
require 'fileutils'
require 'yaml'
require 'open-uri'
require 'nokogiri'

class KatabaTest < Minitest::Test
  FIXTURE_DIR = File.expand_path('fixtures', __dir__)

  MODS_URI  = "http://www.loc.gov/standards/mods/v3/mods-3-5.xsd"
  XLINK_URI = "http://www.loc.gov/standards/xlink/xlink.xsd"
  XML_URI   = "http://www.loc.gov/mods/xml.xsd"

  MIRROR_MODS  = "https://raw.githubusercontent.com/dgcliff/kataba/master/test/fixtures/mods-3-5.xsd"
  MIRROR_XLINK = "https://raw.githubusercontent.com/dgcliff/kataba/master/test/fixtures/xlink.xsd"
  MIRROR_XML   = "https://raw.githubusercontent.com/dgcliff/kataba/master/test/fixtures/xml.xsd"

  BAD_MIRROR = "https://www.google.com/broken"

  def setup
    FileUtils.rm_rf(Kataba.configuration.offline_storage)
    # Reset so each test gets clean assert_(not_)requested counts.
    WebMock.reset!

    # Stub canonical LoC URLs (used when no mirror is configured)
    stub_request(:get, MODS_URI).to_return(status: 200, body: File.read("#{FIXTURE_DIR}/mods-3-5.xsd"))
    stub_request(:get, XLINK_URI).to_return(status: 200, body: File.read("#{FIXTURE_DIR}/xlink.xsd"))
    stub_request(:get, XML_URI).to_return(status: 200, body: File.read("#{FIXTURE_DIR}/xml.xsd"))

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

  def test_bad_mirror_list
    mirror_list = YAML.load_file(Dir.pwd + '/test/fixtures/bad_mirror.yml')
    assert_equal BAD_MIRROR, mirror_list[MODS_URI]

    Kataba.configuration.mirror_list = Dir.pwd + '/test/fixtures/bad_mirror.yml'

    assert_raises(OpenURI::HTTPError) { Kataba.fetch_schema(MODS_URI) }
  end
end
