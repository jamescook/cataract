require "bundler/gem_tasks"
require "rake/testtask"

# Only load extension task if rake-compiler is available
begin
  require "rake/extensiontask"

  # Configure the extension
  Rake::ExtensionTask.new("cataract") do |ext|
    ext.lib_dir = "lib/cataract"
    ext.ext_dir = "ext/cataract"

    # Use fast compilation for local development
    # Gem builds will use -G2 automatically (see extconf.rb)
    ENV['CATARACT_DEV_BUILD'] = '1' if ENV['CATARACT_DEV_BUILD'].nil?
  end
end

# Test task
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

task :benchmark do
  Rake::Task[:compile].invoke
  
  puts "Running benchmark with development version..."
  ruby "test/benchmark.rb"
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
