require "bundler/gem_tasks"
require "rake/testtask"

# Only load extension task if rake-compiler is available
begin
  require "rake/extensiontask"

  # Configure the extension
  Rake::ExtensionTask.new("cataract") do |ext|
    ext.lib_dir = "lib/cataract"
    ext.ext_dir = "ext/cataract"
  end
end

# Test task
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  # Exclude css_parser_compat directory (reference tests only, not run)
  t.test_files = FileList["test/**/test_*.rb"].exclude("test/css_parser_compat/**/*")
end

desc "Run all benchmarks"
task :benchmark do
  Rake::Task[:compile].invoke
  Rake::Task["benchmark:parsing"].invoke
  Rake::Task["benchmark:specificity"].invoke
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
    results_files = [
      'test/benchmark_string_allocation_parse.json',
      'test/benchmark_string_allocation_iterate.json',
      'test/benchmark_string_allocation_10x.json'
    ]
    results_files.each do |file|
      if File.exist?(file)
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

# Clean task FIXME if this is chained onto compile it fails???
task :clean do
  puts "Cleaning build artifacts..."
  
  files_to_clean = [
    "lib/cataract/cataract.so",
    "ext/cataract/cataract.c",
    "ext/cataract/Makefile",
    "ext/cataract/*.o"
  ]
  
  files_to_clean.each do |pattern|
    Dir.glob(pattern).each do |file|
      puts "  Removing #{file}"
      FileUtils.rm_f(file)
    end
  end
  
  if Dir.exist?("tmp/")
    puts "  Removing tmp/"
    FileUtils.rm_rf("tmp/")
  end
  
  puts "Clean complete"
end

task compile: :clean
task test: :compile

task default: :test
