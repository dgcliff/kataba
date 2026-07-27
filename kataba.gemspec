Gem::Specification.new do |s|
  s.name        = 'kataba'
  s.version     = '1.1.2'
  s.date        = '2026-05-18'
  s.summary     = "XML Schema Definition (XSD) mirroring and offline validation for Nokogiri"
  s.description = "Kataba allows for mirroring and offline storage of XSD files, to enhance Nokogiri"
  s.authors     = ["David Cliff"]
  s.email       = 'd.cliff@northeastern.edu'
  s.files       = ["lib/kataba.rb", "lib/kataba/fetcher.rb"]
  s.homepage    =
    'http://rubygems.org/gems/kataba'
  s.license       = 'MIT'
  s.required_ruby_version = '>= 3.2'

  s.add_dependency "nokogiri", '>= 1.19'

  s.add_development_dependency "rake"
  s.add_development_dependency "minitest"
  s.add_development_dependency "webmock"
end
