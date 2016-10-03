require 'minitest/autorun'
require 'kataba'
require 'fileutils'
require 'yaml'
require 'open-uri'
require 'nokogiri'

class KatabaTest < Minitest::Unit::TestCase
  def test_xsd_return
    FileUtils.rm_rf(Kataba.configuration.offline_storage)

    assert_kind_of Nokogiri::XML::Schema,
      Kataba.fetch_schema("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd")

    Kataba.reset
  end

  def test_custom_directory
    FileUtils.rm_rf(Kataba.configuration.offline_storage)

    full_path = "#{Dir.pwd}/xsd_files"
    Kataba.configuration.offline_storage = full_path
    Kataba.fetch_schema("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd")
    assert File.file?(full_path + "/01490ebdea13c1bc82a17e4783daeeaa.xsd")
    assert File.file?(full_path + "/534d7d1e9b53ece0bf0f5874444d8bcb.xsd")
    assert File.file?(full_path + "/c547c5ba5338defc42b59e2904542d30.xsd")
    FileUtils.rm_rf(full_path)

    Kataba.reset
  end

  def test_default_directory
    FileUtils.rm_rf(Kataba.configuration.offline_storage)

    assert Dir.exists?(File.expand_path("..", Kataba.configuration.offline_storage))

    Kataba.reset
  end

  def test_mirror_list
    FileUtils.rm_rf(Kataba.configuration.offline_storage)

    mirror_list = YAML.load_file(Dir.pwd + '/test/fixtures/mirror.yml')
    assert mirror_list["http://www.loc.gov/standards/mods/v3/mods-3-5.xsd"] == "https://raw.githubusercontent.com/dgcliff/kataba/master/test/fixtures/mods-3-5.xsd"
    assert Nokogiri::XML(open("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd").read,&:noblanks).to_s == Nokogiri::XML(open("https://raw.githubusercontent.com/dgcliff/kataba/master/test/fixtures/mods-3-5.xsd"),&:noblanks).to_s

    Kataba.configuration.mirror_list = Dir.pwd + '/test/fixtures/mirror.yml'

    assert_kind_of Nokogiri::XML::Schema,
      Kataba.fetch_schema("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd")

    Kataba.reset
  end

  def test_bad_mirror_list
    FileUtils.rm_rf(Kataba.configuration.offline_storage)
    mirror_list = YAML.load_file(Dir.pwd + '/test/fixtures/bad_mirror.yml')
    assert mirror_list["http://www.loc.gov/standards/mods/v3/mods-3-5.xsd"] == "https://www.google.com/broken"

    Kataba.configuration.mirror_list = Dir.pwd + '/test/fixtures/bad_mirror.yml'

    assert_raises(OpenURI::HTTPError){Kataba.fetch_schema("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd")}      

    Kataba.reset
  end
end
