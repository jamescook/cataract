require 'mkmf'
require_relative 'ragel_generator'

# Generate C code from Ragel grammars
RagelGenerator.generate_c_from_ragel(ext_dir: File.dirname(__FILE__))

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
