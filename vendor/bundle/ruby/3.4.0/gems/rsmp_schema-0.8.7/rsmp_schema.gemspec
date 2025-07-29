lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'pathname'
require_relative "lib/rsmp_schema/version"

Gem::Specification.new do |spec|
  spec.name          = "rsmp_schema"
  spec.version       = RSMP::Schema::VERSION
  spec.authors       = ["Emil Tin"]
  spec.email         = ["zf0f@kk.dk"]

  spec.summary       = "Validate RSMP message against RSMP JSON Schema."
  spec.description   = "Validate RSMP message against RSMP JSON Schema. Support validating against core and different SXL's, in different versions."
  spec.homepage      = "https://github.com/rsmp-nordic/rsmp_schema"
  spec.licenses      = ['MIT']
  spec.required_ruby_version = '>= 3.0.0'

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "json_schemer", "~> 2.3.0"
  spec.add_dependency "thor", "~> 1.3.1"

  spec.add_development_dependency "rake", "~> 13.2.1"
  spec.add_development_dependency "rspec", "~> 3.13.0"
  spec.add_development_dependency "rspec-expectations", "~> 3.13.0"
end
