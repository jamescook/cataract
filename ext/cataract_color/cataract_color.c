// cataract_color.c - Color conversion extension entry point
// This is a separate extension loaded on-demand via require 'cataract/color_conversion'

#include <ruby.h>

// Forward declaration from color_conversion.c
void Init_color_conversion(VALUE mCataract);

// Extension initialization - called when the .so is loaded
void Init_cataract_color(void) {
    // Get the Cataract module (must already be loaded by main extension)
    VALUE mCataract = rb_const_get(rb_cObject, rb_intern("Cataract"));

    // Initialize color conversion methods on Cataract::Stylesheet
    Init_color_conversion(mCataract);
}
