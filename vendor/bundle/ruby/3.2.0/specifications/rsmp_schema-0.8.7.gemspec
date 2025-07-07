# -*- encoding: utf-8 -*-
# stub: rsmp_schema 0.8.7 ruby lib

Gem::Specification.new do |s|
  s.name = "rsmp_schema".freeze
  s.version = "0.8.7"

  s.required_rubygems_version = Gem::Requirement.new(">= 0".freeze) if s.respond_to? :required_rubygems_version=
  s.metadata = { "bug_tracker_uri" => "https://github.com/rsmp-nordic/rsmp_schema/issues", "changelog_uri" => "https://github.com/rsmp-nordic/rsmp_schema/CHANGELOG.md", "homepage_uri" => "https://github.com/rsmp-nordic/rsmp_schema", "source_code_uri" => "https://github.com/rsmp-nordic/rsmp_schema" } if s.respond_to? :metadata=
  s.require_paths = ["lib".freeze]
  s.authors = ["Emil Tin".freeze]
  s.bindir = "exe".freeze
  s.date = "2025-03-04"
  s.description = "Validate RSMP message against RSMP JSON Schema. Support validating against core and different SXL's, in different versions.".freeze
  s.email = ["zf0f@kk.dk".freeze]
  s.executables = ["rsmp_schema".freeze]
  s.files = ["exe/rsmp_schema".freeze]
  s.homepage = "https://github.com/rsmp-nordic/rsmp_schema".freeze
  s.licenses = ["MIT".freeze]
  s.required_ruby_version = Gem::Requirement.new(">= 3.0.0".freeze)
  s.rubygems_version = "3.4.20".freeze
  s.summary = "Validate RSMP message against RSMP JSON Schema.".freeze

  s.installed_by_version = "3.4.20" if s.respond_to? :installed_by_version

  s.specification_version = 4

  s.add_runtime_dependency(%q<json_schemer>.freeze, ["~> 2.3.0"])
  s.add_runtime_dependency(%q<thor>.freeze, ["~> 1.3.1"])
  s.add_development_dependency(%q<rake>.freeze, ["~> 13.2.1"])
  s.add_development_dependency(%q<rspec>.freeze, ["~> 3.13.0"])
  s.add_development_dependency(%q<rspec-expectations>.freeze, ["~> 3.13.0"])
end
