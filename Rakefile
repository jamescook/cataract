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
    ENV['CATARACT_DEV_BUILD'] = '1'
  end

  EXTENSION_AVAILABLE = true
rescue LoadError
  EXTENSION_AVAILABLE = false
  puts "rake-compiler not available. Run 'bundle install' to enable C extension building."
end

# Test task
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

# Compile Ragel grammar for pure Ruby version
task :compile_ruby_grammar do
  puts "Compiling Ragel grammar for Ruby..."

  input_file = "lib/cataract/pure_ruby_parser.rb"
  output_file = "lib/cataract/pure_ruby_parser_compiled.rb"
  
  if File.exist?(input_file)
    puts "  Input: #{input_file}"
    puts "  Output: #{output_file}"
    
    if system("ragel -R #{input_file} -o #{output_file}")
      # Replace the original file with the compiled version
      File.rename(output_file, input_file)
      puts "Ruby grammar compiled successfully"
    else
      puts "ERROR: Failed to compile Ruby grammar"
      puts "Make sure ragel is installed and the grammar is valid"
      exit 1
    end
  else
    puts "ERROR: Ruby grammar file not found: #{input_file}"
    exit 1
  end
end

# Benchmark task
task :benchmark do
  # Ensure we have the latest compiled version
  Rake::Task[:compile_ruby_grammar].invoke unless File.exist?("lib/cataract/pure_ruby_parser.rb")
  
  if EXTENSION_AVAILABLE
    Rake::Task[:compile].invoke
  end
  
  puts "Running benchmark with development version..."
  ruby "test/benchmark.rb"
end

# Clean task
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

# Make test depend on compilation
if EXTENSION_AVAILABLE
  task test: [:compile_ruby_grammar, :compile]
else
  task test: [:compile_ruby_grammar]
end

task default: :test
