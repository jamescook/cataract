require_relative 'lib/cataract/version'

Gem::Specification.new do |spec|
  spec.name          = "cataract"
  spec.version       = Cataract::VERSION
  spec.authors       = ["Your Name"]
  spec.email         = ["your.email@example.com"]

  spec.summary       = %q{CSS parser built with Ragel state machines}
  spec.description   = %q{A high-performance CSS parser using Ragel finite state machines for accurate parsing of complex CSS structures}
  spec.homepage      = "https://github.com/jamescook/cataract"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path('..', __FILE__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end

  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # C extension configuration
  spec.extensions = ["ext/cataract/extconf.rb"]

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rake-compiler", "~> 1.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "benchmark-ips", "~> 2.0"
  spec.add_development_dependency "css_parser", "~> 1.0" # for benchmarking

  # Runtime dependencies (none for now)
end
