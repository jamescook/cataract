# frozen_string_literal: true

require 'mkmf'

# Helper methods for platform detection
def darwin?
  RbConfig::CONFIG['target_os'].include?('darwin')
end

def linux?
  RbConfig::CONFIG['target_os'].include?('linux')
end

# Configuration options (use --enable-OPTION or --disable-OPTION)
def config_debug?
  enable_config('debug', false)
end

def config_str_buf_optimization?
  # Default to enabled (optimization ON)
  enable_config('str-buf-optimization', true)
end

# Compile main file, parser, merge, and supporting files
$objs = ['cataract.o', 'css_parser.o', 'merge.o', 'shorthand_expander.o', 'specificity.o', 'value_splitter.o',
         'import_scanner.o']

# Suppress warnings
$CFLAGS << ' -Wno-unused-const-variable' if darwin? || linux?
$CFLAGS << ' -Wno-shorten-64-to-32' if darwin?
$CFLAGS << ' -Wno-unused-variable'

# Apply configuration flags
if config_debug?
  $CFLAGS << ' -DCATARACT_DEBUG=1'
  puts 'Debug mode: ENABLED'
else
  puts 'Debug mode: disabled'
end

if config_str_buf_optimization?
  puts 'String buffer optimization: enabled (default)'
else
  $CFLAGS << ' -DDISABLE_STR_BUF_OPTIMIZATION=1'
  puts 'String buffer optimization: DISABLED'
end

create_makefile('cataract/native_extension')
