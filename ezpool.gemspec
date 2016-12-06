# -*- encoding: utf-8 -*-
require "./lib/ezpool/version"

Gem::Specification.new do |s|
  s.name        = "ezpool"
  s.version     = EzPool::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ["Mike Perham", "Damian Janowski", "James Brown"]
  s.email       = ["oss@easypost.com"]
  s.homepage    = "https://github.com/EasyPost/ezpool"
  s.description = s.summary = %q{More featureful generic connection pool for Ruby}

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.license = "MIT"
  s.add_development_dependency 'bundler'
  s.add_development_dependency 'minitest', '>= 5.0.0'
  s.add_development_dependency 'rake'
end
