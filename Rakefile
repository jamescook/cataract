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

task :benchmark do
  Rake::Task[:compile].invoke

  puts "Running benchmark with development version..."
  ruby "test/benchmark.rb"
end

namespace :benchmark do
  desc "Benchmark different Ragel code generation styles"
  task :styles do
    puts "Benchmarking Ragel code generation styles..."
    puts "This will compile the extension multiple times with different styles."
    puts ""
    ruby "test/benchmark_ragel_styles.rb"
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
