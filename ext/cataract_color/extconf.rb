# frozen_string_literal: true

require 'mkmf'

# Add include path for cataract.h from main extension
$INCFLAGS << ' -I$(srcdir)/../cataract'

# Color conversion extension - separate from core parser
# Compile C files:
# - cataract_color.c (extension entry point)
# - color_conversion.c (main conversion dispatcher)
# - color_conversion_oklab.c (Oklab color space conversions)
# - color_conversion_lab.c (CIE L*a*b* color space conversions)
# - color_conversion_named.c (CSS named colors)
$objs = ['cataract_color.o', 'color_conversion.o', 'color_conversion_oklab.o', 'color_conversion_lab.o',
         'color_conversion_named.o']

# Suppress warnings
$CFLAGS << ' -Wno-unused-const-variable' if RUBY_PLATFORM.match?(/darwin|linux/)
$CFLAGS << ' -Wno-shorten-64-to-32' if RUBY_PLATFORM.include?('darwin')
$CFLAGS << ' -Wno-unused-variable'

create_makefile('cataract/cataract_color')
