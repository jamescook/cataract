# frozen_string_literal: true

require_relative 'lib/cataract/version'

Gem::Specification.new do |spec|
  spec.name          = 'cataract'
  spec.version       = Cataract::VERSION
  spec.authors       = ['James Cook']
  spec.email         = ['jcook.rubyist@gmail.com']

  spec.summary       = 'High-performance CSS parser with C extensions'
  spec.description   = 'A performant CSS parser with C extensions for accurate parsing of complex CSS structures including media queries, nested selectors, and CSS Color Level 4'
  spec.homepage      = 'https://github.com/jamescook/cataract'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.1.0')

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) || f.match(/^test_.*\.rb$/) }
  end

  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # C extension configuration
  # Two separate extensions: core parser and optional color conversion
  spec.extensions = ['ext/cataract/extconf.rb', 'ext/cataract_color/extconf.rb']
end
