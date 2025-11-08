# frozen_string_literal: true

require 'mkmf'

# Compile main file, parser, merge, and supporting files
$objs = ['cataract.o', 'css_parser.o', 'merge.o', 'shorthand_expander.o', 'specificity.o', 'value_splitter.o',
         'import_scanner.o']

# Suppress warnings
$CFLAGS << ' -Wno-unused-const-variable' if RUBY_PLATFORM.match?(/darwin|linux/)
$CFLAGS << ' -Wno-shorten-64-to-32' if RUBY_PLATFORM.include?('darwin')
$CFLAGS << ' -Wno-unused-variable'

create_makefile('cataract/cataract')
