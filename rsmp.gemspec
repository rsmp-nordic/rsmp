lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rsmp/version"
require 'pathname'

Gem::Specification.new do |spec|
  spec.name          = "rsmp"
  spec.version       = RSMP::VERSION
  spec.authors       = ["Emil Tin"]
  spec.email         = ["zf0f@kk.dk"]

  spec.summary       = %q{RoadSide Message Protocol (RSMP) library.}
  spec.description   = %q{Easy RSMP site and supervisor communication.}
  spec.homepage      = "https://github.com/rsmp-nordic/rsmp"
  spec.licenses      = ['MIT']
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rsmp-nordic/rsmp"
  spec.metadata["changelog_uri"] = "https://github.com/rsmp-nordic/rsmp/blob/master/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/rsmp-nordic/rsmp/issues"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 2.12.0"
  spec.add_dependency "async-io", "~> 1.43.2"
  spec.add_dependency "colorize", "~> 1.1"
  spec.add_dependency "rsmp_schema", "~> 0.6.0"

  spec.add_development_dependency "bundler", "~> 2.5.11"
  spec.add_development_dependency "rake", "~> 13.2.0"
  spec.add_development_dependency "rspec", "~> 3.13.0"
  spec.add_development_dependency "rspec-expectations", "~> 3.13.0"
  spec.add_development_dependency "timecop", "~> 0.9.8"
  spec.add_development_dependency "cucumber", "~> 9.2.0"
  spec.add_development_dependency "aruba" , "~> 2.2.0"
end
