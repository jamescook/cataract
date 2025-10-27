require "bundler/gem_tasks"
require "rake/testtask"
require "rake/clean"

# Only load extension task if rake-compiler is available
begin
  require "rake/extensiontask"

  # Configure the extension
  Rake::ExtensionTask.new("cataract") do |ext|
    ext.lib_dir = "lib/cataract"
    ext.ext_dir = "ext/cataract"
  end
end

# Configure CLEAN to run before compilation
# rake-compiler already adds: tmp/, lib/**/*.{so,bundle}, etc.
# We clean Ragel-generated .c files (regenerated from .rl), but keep hand-written .c files
# Only clean: cataract.c and shorthand_expander.c (generated from .rl files)
CLEAN.include("ext/cataract/cataract.c", "ext/cataract/shorthand_expander.c",
              "ext/**/Makefile", "ext/**/*.o")

# Test task
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  # Load test_helper before running tests (handles SimpleCov setup)
  t.ruby_opts << "-rtest_helper"
  # Exclude css_parser_compat directory (reference tests only, not run)
  t.test_files = FileList["test/**/test_*.rb"].exclude("test/css_parser_compat/**/*")
end

desc "Run all benchmarks"
task :benchmark do
  Rake::Task[:compile].invoke
  Rake::Task["benchmark:parsing"].invoke
  Rake::Task["benchmark:specificity"].invoke
  Rake::Task["benchmark:merging"].invoke
end

namespace :benchmark do
  desc "Benchmark CSS parsing performance"
  task :parsing do
    Rake::Task[:compile].invoke
    puts "Running parsing benchmark..."
    ruby "test/benchmarks/benchmark_parsing.rb"
  end

  desc "Benchmark specificity calculation performance"
  task :specificity do
    Rake::Task[:compile].invoke
    puts "Running specificity benchmark..."
    ruby "test/benchmarks/benchmark_specificity.rb"
  end

  desc "Benchmark CSS merging performance"
  task :merging do
    Rake::Task[:compile].invoke
    puts "Running merging benchmark..."
    ruby "test/benchmarks/benchmark_merging.rb"
  end

  desc "Benchmark different Ragel code generation styles"
  task :styles do
    puts "Benchmarking Ragel code generation styles..."
    puts "This will compile the extension multiple times with different styles."
    puts ""
    ruby "test/benchmark_ragel_styles.rb"
  end

  desc "Benchmark Ruby-side operations with YJIT on vs off"
  task :yjit do
    Rake::Task[:compile].invoke
    puts "\n" + "=" * 80
    puts "Running with YJIT OFF"
    puts "=" * 80
    system({'RUBY_YJIT_ENABLE' => '0'}, RbConfig.ruby, "test/benchmarks/benchmark_yjit.rb")

    puts "\n\n" + "=" * 80
    puts "Running with YJIT ON"
    puts "=" * 80
    system({'RUBY_YJIT_ENABLE' => '1'}, RbConfig.ruby, "test/benchmarks/benchmark_yjit.rb")
  end

  desc "Benchmark string allocation optimization (buffer vs dynamic)"
  task :string_allocation do
    # Clean up any existing benchmark results
    results_dir = 'test/.benchmark_results'
    if Dir.exist?(results_dir)
      Dir.glob(File.join(results_dir, 'string_allocation_*.json')).each do |file|
        puts "Removing old benchmark results: #{file}"
        FileUtils.rm_f(file)
      end
    end

    puts "\n" + "=" * 80
    puts "Compiling with DYNAMIC allocation (rb_str_new_cstr)"
    puts "=" * 80
    system({'DISABLE_STR_BUF_OPTIMIZATION' => '1'}, 'rake', 'compile')
    system({}, RbConfig.ruby, "test/benchmarks/benchmark_string_allocation.rb")

    puts "\n\n" + "=" * 80
    puts "Compiling with BUFFER allocation (rb_str_buf_new, production default)"
    puts "=" * 80
    system({}, 'rake', 'compile')
    system({}, RbConfig.ruby, "test/benchmarks/benchmark_string_allocation.rb")
  end
end

task compile: :clean
task test: :compile

task default: :test

namespace :compile do
  # Generate C code from Ragel grammars
  desc "Generate C code from Ragel (.rl) files"
  task :ragel do
    require_relative 'ext/cataract/ragel_generator'
    RagelGenerator.generate_c_from_ragel
  end
end

# Lint task - runs cppcheck on generated C code
desc "Run cppcheck on generated C code"
task lint: 'compile:ragel' do
  # Check if cppcheck is installed
  unless system("which cppcheck > /dev/null 2>&1")
    abort("cppcheck not installed. Install with: brew install cppcheck (macOS) or apt-get install cppcheck (Ubuntu)")
  end

  puts "Running cppcheck on C code..."

  # Run cppcheck on all C files:
  # - cataract.c (Ragel-generated parser)
  # - shorthand_expander.c (Ragel-generated shorthand logic)
  # - merge.c (CSS cascade/merge logic)
  # - stylesheet.c (serialization logic)
  #
  # Focus on serious issues, skip style noise from Ragel-generated code
  # --enable=warning,performance,portability: serious issues only (skip 'style')
  # --suppress=missingIncludeSystem: ignore system header issues
  # --suppress=normalCheckLevelMaxBranches: skip exhaustive analysis suggestion (too slow for generated code)
  # --inline-suppr: allow inline suppressions in code
  # --error-exitcode=1: exit with 1 if errors found
  # -q: quiet mode, less verbose
  # -I ext/cataract: include path for cataract.h header
  system("cppcheck --enable=warning,performance,portability --suppress=missingIncludeSystem --suppress=normalCheckLevelMaxBranches --inline-suppr -q -I ext/cataract ext/cataract/*.c") ||
    abort("cppcheck found issues!")

  puts "✓ cppcheck passed (warnings/errors only, style checks skipped)"
end

# Fuzz testing
desc "Run fuzzer to test parser robustness"
task fuzz: :compile do
  iterations = ENV['ITERATIONS'] || '10000'
  puts "Running CSS parser fuzzer (#{iterations} iterations)..."
  # Use system with ENV.to_h to preserve environment variables like FUZZ_GC_STRESS
  system(ENV.to_h, RbConfig.ruby, '-Ilib', 'test/fuzz_css_parser.rb', iterations)
end
