require 'mkmf'

ragel_version = `ragel --version 2>/dev/null`
if $?.success?
  puts "Found Ragel: #{ragel_version.strip}"
else
  puts "ERROR: Ragel not found. Please install ragel:"
  puts "  macOS: brew install ragel"
  puts "  Ubuntu: sudo apt-get install ragel"
  puts "  Or download from: http://www.colm.net/open-source/ragel/"
  exit 1
end

# Get the correct path to the .rl files
ext_dir = File.dirname(__FILE__)

# Ragel code generation style
# Defaults to -T0 (table driven, balances speed and compile time)
# Override with RAGEL_STYLE environment variable to test other styles
# Available: -T0, -T1, -F0, -F1, -G0, -G1, -G2 (see ragel --help)
ragel_style = ENV['RAGEL_STYLE'] || '-T0'
ragel_flags = "#{ragel_style} -C"

# Generate C code from all Ragel grammars
# Note: shorthand_expander.c is included in cataract.c, not compiled separately
ragel_files = [
  ['cataract.rl', 'cataract.c'],
  ['shorthand_expander.rl', 'shorthand_expander.c']
]

ragel_files.each do |rl_name, c_name|
  rl_file = File.join(ext_dir, rl_name)
  c_file = File.join(ext_dir, c_name)

  unless File.exist?(rl_file)
    puts "ERROR: Ragel grammar file not found: #{rl_file}"
    exit 1
  end

  puts "Generating C code from Ragel grammar..."
  puts "  Input: #{rl_file}"
  puts "  Output: #{c_file}"
  puts "  Style: #{ragel_style}"

  ragel_cmd = "ragel #{ragel_flags} #{rl_file} -o #{c_file}"
  unless system(ragel_cmd)
    puts "ERROR: Failed to generate C code from Ragel grammar"
    puts "Command: #{ragel_cmd}"
    exit 1
  end

  unless File.exist?(c_file)
    puts "ERROR: Generated C file not found: #{c_file}"
    exit 1
  end

  puts "Generated #{c_name} successfully"
end

# Only compile cataract.c (it includes value_splitter.c)
$objs = ['cataract.o']

# String buffer optimization (enabled by default, disable for benchmarking)
# Check both env var (for development) and command-line flag (for gem install)
if ENV['DISABLE_STR_BUF_OPTIMIZATION'] || arg_config('--disable-str-buf-optimization')
  puts "Disabling string buffer pre-allocation optimization (baseline mode for benchmarking)"
  $CFLAGS << " -DDISABLE_STR_BUF_OPTIMIZATION"
else
  puts "Using string buffer pre-allocation optimization (rb_str_buf_new)"
end

# Suppress warnings from Ragel-generated code
# The generated C code has some harmless warnings we can't fix
$CFLAGS << " -Wno-unused-const-variable" if RUBY_PLATFORM =~ /darwin|linux/
$CFLAGS << " -Wno-shorten-64-to-32" if RUBY_PLATFORM =~ /darwin/
$CFLAGS << " -Wno-unused-variable"

create_makefile('cataract/cataract')
