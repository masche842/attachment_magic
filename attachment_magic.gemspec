# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "attachment_magic/version"

Gem::Specification.new do |s|
  s.name        = "attachment_magic"
  s.version     = AttachmentMagic::VERSION
  s.authors     = ["Thomas von Deyen"]
  s.email       = ["tvdeyen@gmail.com"]
  s.homepage    = "https://github.com/magiclabs/attachment_magic"
  s.summary     = %q{A simple file attachment gem for Rails 3}
  s.description = %q{A Rails 3 Gem based on attachment_fu, but without the image processing fudge and multiple backend crap! Just simple file attachments with a little mime type magic ;)}

  s.rubyforge_project = "attachment_magic"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]
  s.add_runtime_dependency(%q<rails>, ["< 3.1", ">= 3.0.7"])
  s.add_runtime_dependency(%q<mimetype-fu>, ["~> 0.1.2"])
end
