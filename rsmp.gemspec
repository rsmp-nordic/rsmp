lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "rsmp/version"

Gem::Specification.new do |spec|
  spec.name          = "rsmp"
  spec.version       = Rsmp::VERSION
  spec.authors       = ["Emil Tin"]
  spec.email         = ["zf0f@kk.dk"]

  spec.summary       = %q{RoadSide Message Protocol (RSMP) library.}
  spec.description   = %q{Easy RSMP site and supervisor communication.}
  spec.homepage      = "https://github.com/rsmp-nordic/rsmp"

  spec.metadata["allowed_push_host"] = "https://github.com/rsmp-nordic/rsmp" #TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/rsmp-nordic/rsmp" #"TODO: Put your gem's public repo URL here."
  spec.metadata["changelog_uri"] = "https://github.com/rsmp-nordic/rsmp" #"TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files         = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "async", "~> 1.20.1"
  spec.add_dependency "async-io", "~> 1.24.0"
  spec.add_dependency "colorize", "~> 0.8.1"
  spec.add_dependency "thor"

  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-expectations", "~> 3.8.3"
  spec.add_development_dependency "rspec-with_params", "~> 0.2.0"
  spec.add_development_dependency "timecop", "~> 0.9.1"
  spec.add_development_dependency "cucumber", "~> 3.1.2"
  spec.add_development_dependency "aruba", "~> 0.14.11"
end
