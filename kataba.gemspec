Gem::Specification.new do |s|
  s.name        = 'kataba'
  s.version     = '0.0.0'
  s.date        = '2016-10-02'
  s.summary     = "XML Schema Definition (XSD) mirroring and offline validation for Nokogiri"
  s.description = "A simple gem that allows for the functionality that an XML catalog would provide"
  s.authors     = ["David Cliff"]
  s.email       = 'd.cliff@northeastern.edu'
  s.files       = ["lib/kataba.rb"]
  s.homepage    =
    'http://rubygems.org/gems/kataba'
  s.license       = 'MIT'
  s.required_ruby_version = '~> 2.0'

  s.add_dependency "nokogiri", '~> 1.6'
end
