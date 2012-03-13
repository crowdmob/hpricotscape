# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "hpricotscape/version"

Gem::Specification.new do |s|
  s.name        = "hpricotscape"
  s.version     = Hpricotscape::VERSION
  s.authors     = ["Matthew Moore", "Rohen Peterson"]
  s.email       = ["matt@crowdmob.com", "rohen@crowdmob.com"]
  s.homepage    = ""
  s.summary     = %q{Use Hpricot and maintain cookies from page to page.}
  s.description = %q{Use Hpricot and maintain cookies from page to page.}

  s.rubyforge_project = "hpricotscape"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
end
