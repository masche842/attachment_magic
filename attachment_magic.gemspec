# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "attachment_magic/version"

Gem::Specification.new do |s|
  s.name        = "attachment_magic"
  s.version     = AttachmentMagic::VERSION
  s.authors     = ["Thomas von Deyen"]
  s.email       = ["tvdeyen@gmail.com"]
  s.homepage    = ""
  s.summary     = %q{TODO: Write a gem summary}
  s.description = %q{TODO: Write a gem description}

  s.rubyforge_project = "attachment_magic"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.add_runtime_dependency(%q<rails>, ["< 3.1", ">= 3.0.7"])
end
