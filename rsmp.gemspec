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
  spec.required_ruby_version = '>= 2.0.0'

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rsmp-nordic/rsmp"
  spec.metadata["changelog_uri"] = "https://github.com/rsmp-nordic/rsmp/blob/master/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "https://github.com/rsmp-nordic/rsmp/issues"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  # Add schema files in rsmp_schema submodule
  gem_dir = Pathname.new(__dir__).expand_path
  submodule_path = File.expand_path 'lib/rsmp_schema/schema'
  Dir.chdir(submodule_path) do
    submodule_relative_path = Pathname.new(submodule_path).relative_path_from(gem_dir)
    `git ls-files`.split($\).each do |filename|
      # for each git file, prepend relative submodule path and add to spec
      spec.files << submodule_relative_path.join(filename).to_s
    end
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 1.28.7"
  spec.add_dependency "async-io", "~> 1.30.2"
  spec.add_dependency "colorize", "~> 0.8.1"
  spec.add_dependency "thor", "~> 1.0.1"
  #spec.add_dependency "json_schemer", "~> 0.2.18"

  spec.add_development_dependency "bundler", "~> 2.2.3"
  spec.add_development_dependency "rake", "~> 13.0.1"
  spec.add_development_dependency "rspec", "~> 3.9.0"
  spec.add_development_dependency "rspec-expectations", "~> 3.9.1"
  spec.add_development_dependency "timecop", "~> 0.9.1"
  spec.add_development_dependency "cucumber", "~> 3.1.2"
  spec.add_development_dependency "aruba", "~> 1.0.0"
end
