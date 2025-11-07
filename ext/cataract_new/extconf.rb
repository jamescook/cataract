# frozen_string_literal: true

require 'mkmf'

# New parallel implementation - stubbed version
# Once stable, this will replace ext/cataract/

# Compile both main file and parser
$objs = ['cataract_new.o', 'css_parser_new.o']

# Suppress warnings
$CFLAGS << ' -Wno-unused-const-variable' if RUBY_PLATFORM.match?(/darwin|linux/)
$CFLAGS << ' -Wno-shorten-64-to-32' if RUBY_PLATFORM.include?('darwin')
$CFLAGS << ' -Wno-unused-variable'

create_makefile('cataract/cataract_new')
