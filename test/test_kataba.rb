require 'minitest/autorun'
require 'kataba'
require 'fileutils'
require 'yaml'
require 'open-uri'

class KatabaTest < Minitest::Unit::TestCase
  def test_xsd_return
    assert_kind_of Nokogiri::XML::Schema,
      Kataba.fetch_schema("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd")
  end

  def test_custom_directory
    # Dir.pwd
    full_path = "#{Dir.pwd}/xsd_files"
    Kataba.configuration.offline_storage = full_path
    Kataba.fetch_schema("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd")
    assert File.file?(full_path + "/01490ebdea13c1bc82a17e4783daeeaa.xsd")
    assert File.file?(full_path + "/534d7d1e9b53ece0bf0f5874444d8bcb.xsd")
    assert File.file?(full_path + "/c547c5ba5338defc42b59e2904542d30.xsd")
    FileUtils.rm_rf(full_path)
  end

  def test_default_directory
    assert Dir.exists?(File.expand_path("..", Kataba.configuration.offline_storage))
  end

  def test_mirror_list
    mirror_list = YAML.load_file(Dir.pwd + '/test/fixtures/mirror.yml')
    assert mirror_list["http://www.loc.gov/standards/mods/v3/mods-3-5.xsd"] == "https://gist.githubusercontent.com/dgcliff/6b7b16438b87008432ce5bb506025339/raw/a792c59b31775e8f7d108f8ec25218e9a65d22c5/mods-3-5.xsd"
    assert open("http://www.loc.gov/standards/mods/v3/mods-3-5.xsd").read == open("https://gist.githubusercontent.com/dgcliff/6b7b16438b87008432ce5bb506025339/raw/a792c59b31775e8f7d108f8ec25218e9a65d22c5/mods-3-5.xsd").read
  end
end
