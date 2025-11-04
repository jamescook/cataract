# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rake/testtask'
require 'rake/clean'

# Only load extension task if rake-compiler is available
begin
  require 'rake/extensiontask'

  # Configure the extension
  Rake::ExtensionTask.new('cataract') do |ext|
    ext.lib_dir = 'lib/cataract'
    ext.ext_dir = 'ext/cataract'
  end
end

# Configure CLEAN to run before compilation
# rake-compiler already adds: tmp/, lib/**/*.{so,bundle}, etc.
# All C files are now hand-written (Ragel removed), so only clean build artifacts
CLEAN.include('ext/**/Makefile', 'ext/**/*.o')

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.libs << 'lib'
  # Load test_helper before running tests (handles SimpleCov setup)
  t.ruby_opts << '-rtest_helper'
  # Exclude css_parser_compat directory (reference tests only, not run)
  t.test_files = FileList['test/**/test_*.rb'].exclude('test/css_parser_compat/**/*')
end

desc 'Run all benchmarks'
task :benchmark do
  Rake::Task[:compile].invoke
  Rake::Task['benchmark:parsing'].invoke
  Rake::Task['benchmark:serialization'].invoke
  Rake::Task['benchmark:specificity'].invoke
  Rake::Task['benchmark:merging'].invoke
  Rake::Task['benchmark:yjit'].invoke
  puts "\n#{'-' * 80}"
  puts 'All benchmarks complete!'
  puts 'Generate documentation with: rake benchmark:generate_docs'
  puts '-' * 80
end

namespace :benchmark do
  desc 'Benchmark CSS parsing performance'
  task :parsing do
    puts 'Running parsing benchmark...'
    ruby 'benchmarks/benchmark_parsing.rb'
  end

  desc 'Benchmark CSS serialization (to_s) performance'
  task :serialization do
    puts 'Running serialization benchmark...'
    ruby 'benchmarks/benchmark_serialization.rb'
  end

  desc 'Benchmark specificity calculation performance'
  task :specificity do
    puts 'Running specificity benchmark...'
    ruby 'benchmarks/benchmark_specificity.rb'
  end

  desc 'Benchmark CSS merging performance'
  task :merging do
    puts 'Running merging benchmark...'
    ruby 'benchmarks/benchmark_merging.rb'
  end

  desc 'Benchmark Ruby-side operations with YJIT on vs off'
  task :yjit do
    puts 'Running YJIT benchmark...'
    ruby 'benchmarks/benchmark_yjit.rb'
  end

  desc 'Benchmark string allocation optimization (buffer vs dynamic)'
  task :string_allocation do
    # Clean up any existing benchmark results
    results_dir = 'benchmarks/.benchmark_results'
    if Dir.exist?(results_dir)
      Dir.glob(File.join(results_dir, 'string_allocation_*.json')).each do |file|
        puts "Removing old benchmark results: #{file}"
        FileUtils.rm_f(file)
      end
    end

    puts "\n#{'=' * 80}"
    puts 'Compiling with DYNAMIC allocation (rb_str_new_cstr)'
    puts '=' * 80
    system({ 'DISABLE_STR_BUF_OPTIMIZATION' => '1' }, 'rake', 'compile')
    system({}, RbConfig.ruby, 'benchmarks/benchmark_string_allocation.rb')

    puts "\n\n#{'=' * 80}"
    puts 'Compiling with BUFFER allocation (rb_str_buf_new, production default)'
    puts '=' * 80
    system({}, 'rake', 'compile')
    system({}, RbConfig.ruby, 'benchmarks/benchmark_string_allocation.rb')
  end

  desc 'Generate BENCHMARKS.md from benchmark results'
  task :generate_docs do
    ruby 'scripts/generate_benchmarks_md.rb'
  end
end

task compile: :clean

task default: :test

# Lint task - runs clang-tidy on C code
desc 'Run clang-tidy on C code'
task :lint do
  # Find clang-tidy binary
  clang_tidy = nil

  # Try system PATH first (Linux, or if user has llvm in PATH)
  if system('which clang-tidy > /dev/null 2>&1')
    clang_tidy = 'clang-tidy'
  # On macOS, check Homebrew LLVM (keg-only, not in PATH by default)
  elsif system('which brew > /dev/null 2>&1')
    llvm_prefix = `brew --prefix llvm 2>/dev/null`.strip
    clang_tidy = "#{llvm_prefix}/bin/clang-tidy" if !llvm_prefix.empty? && File.exist?("#{llvm_prefix}/bin/clang-tidy")
  end

  unless clang_tidy
    abort("clang-tidy not installed.\n  " \
          "macOS: brew install llvm\n  " \
          "Ubuntu/Debian: apt-get install clang-tidy\n  " \
          'Fedora/RHEL: dnf install clang-tools-extra')
  end

  puts 'Running clang-tidy on C code...'

  # Find all .c files in ext/cataract/
  c_files = Dir.glob('ext/cataract/*.c')

  # Run clang-tidy on each file
  # Note: clang-tidy uses the .clang-tidy config file automatically
  # We pass Ruby include path so it can find ruby.h
  ruby_include = RbConfig::CONFIG['rubyhdrdir']
  ruby_arch_include = RbConfig::CONFIG['rubyarchhdrdir']

  success = c_files.all? do |file|
    puts "  Checking #{file}..."
    system(clang_tidy, '--quiet', file, '--',
           "-I#{ruby_include}",
           "-I#{ruby_arch_include}",
           '-Iext/cataract')
  end

  if success
    puts '✓ clang-tidy passed'
  else
    abort('clang-tidy found issues!')
  end
end

# Fuzz testing
desc 'Run fuzzer to test parser robustness'
task fuzz: :compile do
  iterations = ENV['ITERATIONS'] || '10000'
  puts "Running CSS parser fuzzer (#{iterations} iterations)..."
  # Use system with ENV.to_h to preserve environment variables like FUZZ_GC_STRESS
  system(ENV.to_h, RbConfig.ruby, '-Ilib', 'test/fuzz_css_parser.rb', iterations)
end

# Documentation generation with YARD
begin
  require 'yard'

  desc 'Generate example CSS analysis for documentation'
  task :generate_example do
    puts 'Generating GitHub CSS analysis example...'
    # Generate to doc root so it's accessible but not processed by YARD
    system('ruby examples/css_analyzer.rb https://github.com -o doc/github_analysis.html')
  end

  YARD::Rake::YardocTask.new(:doc) do |t|
    t.files = ['lib/**/*.rb', 'ext/**/*.c', '-', 'doc/files/EXAMPLE.md']
    t.options = ['--output-dir', 'doc', '--readme', 'README.md', '--title', 'Cataract - Fast CSS Parser']
  end

  desc 'Generate documentation and open in browser'
  task :docs => [:generate_example, :doc] do
    system('open doc/index.html') if RUBY_PLATFORM =~ /darwin/
    system('xdg-open doc/index.html') if RUBY_PLATFORM =~ /linux/
  end

  desc 'List undocumented code'
  task :undoc do
    system('yard stats --list-undoc')
  end
rescue LoadError
  # YARD not available - skip doc tasks
end
