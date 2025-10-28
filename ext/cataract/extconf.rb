require 'mkmf'

# NOTE: Ragel dependency removed! All parsers are now pure C.
# ragel_generator.rb is no longer used, but kept for historical reference.

# Compile C files:
# - cataract.c (Ruby bindings and initialization)
# - shorthand_expander.c (shorthand property expansion/creation)
# - value_splitter.c (CSS value splitting utility)
# - stylesheet.c (CSS serialization)
# - css_parser.c (main CSS parser)
# - specificity.c (selector specificity calculator)
# - merge.c (CSS cascade and merge logic)
$objs = ['cataract.o', 'shorthand_expander.o', 'value_splitter.o', 'stylesheet.o', 'css_parser.o', 'specificity.o', 'merge.o']

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
