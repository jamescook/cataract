#include <ruby.h>
#include <stdio.h>

%%{
  machine css_parser;
  
  # Actions that build Ruby objects
  action mark_start { mark = p; }
  action mark_prop { prop_mark = p; }
  action mark_val { val_mark = p; }
  
  action capture_selector { 
    selector = rb_str_new(mark, p - mark);
    if (NIL_P(current_selectors)) {
      current_selectors = rb_ary_new();
    }
    rb_ary_push(current_selectors, selector);
  }
  
  action capture_property {
    property = rb_str_new(prop_mark, p - prop_mark);
  }
  
  action capture_value {
    VALUE val_str = rb_str_new(val_mark, p - val_mark);
    value = rb_funcall(val_str, rb_intern("strip"), 0);
  }
  
  action finish_declaration {
    if (NIL_P(current_declarations)) {
      current_declarations = rb_hash_new();
    }
    rb_hash_aset(current_declarations, property, value);
  }
  
  action finish_rule {
    // Create one rule for each selector in the list
    if (!NIL_P(current_selectors) && !NIL_P(current_declarations)) {
      long len = RARRAY_LEN(current_selectors);
      for (long i = 0; i < len; i++) {
        VALUE sel = RARRAY_AREF(current_selectors, i);
        VALUE rule = rb_hash_new();
        rb_hash_aset(rule, ID2SYM(rb_intern("selector")), sel);
        rb_hash_aset(rule, ID2SYM(rb_intern("declarations")), rb_hash_dup(current_declarations));
        rb_ary_push(rules_array, rule);
      }
    }
    current_selectors = Qnil;
    current_declarations = Qnil;
  }
  
  # Grammar tokens
  ws = [ \t\n\r];
  comment = '/*' any* '*/';
  ident = alpha (alpha | digit | '-')*;
  number = digit+ ('.' digit+)?;
  dstring = '"' (any - '"')* '"';
  sstring = "'" (any - "'")* "'";
  string = dstring | sstring;
  
  # Simple value that captures everything until ; or }
  value = (any - [;}])+;
  
  # Selectors with attribute support
  class_sel = ('.' ident) >mark_start %capture_selector;
  id_sel = ('#' ident) >mark_start %capture_selector;
  type_sel = ident >mark_start %capture_selector;
  
  # Attribute selectors with optional values
  attr_sel = ('[' ws* ident ws* ('=' ws* (ident | string) ws*)? ']') >mark_start %capture_selector;
  
  simple_selector = attr_sel | class_sel | id_sel | type_sel;
  selector_list = simple_selector (ws* ',' ws* simple_selector)*;
  
  # Declarations with multiple declaration support
  property = ident >mark_prop %capture_property;
  declaration = property ws* ':' ws* (value >mark_val %capture_value) %finish_declaration;
  declaration_list = declaration (ws* ';' ws* declaration)* (ws* ';')?;
  
  # Rules
  rule_body = '{' ws* declaration_list ws* '}' %finish_rule;
  rule = selector_list ws* rule_body;
  
  # Main stylesheet
  stylesheet = (rule | comment | ws)*;
  main := stylesheet;
}%%

%% write data;

static VALUE parse_css(VALUE self, VALUE css_string) {
    // Ragel state variables
    char *p, *pe, *eof;
    char *mark = NULL, *prop_mark = NULL, *val_mark = NULL;
    int cs;
    
    // Ruby variables for building result
    VALUE rules_array, current_selectors, current_declarations, selector, property, value;
    
    // Setup input
    Check_Type(css_string, T_STRING);
    p = RSTRING_PTR(css_string);
    pe = p + RSTRING_LEN(css_string);
    eof = pe;
    
    // Initialize result array and working variables
    rules_array = rb_ary_new();
    current_selectors = Qnil;
    current_declarations = Qnil;
    
    %% write init;
    %% write exec;
    
    if (cs >= css_parser_first_final) {
        return rules_array;
    } else {
        rb_raise(rb_eRuntimeError, "Parse error at position %ld", p - RSTRING_PTR(css_string));
    }
}

// Ruby extension initialization
void Init_cataract() {
    VALUE module = rb_define_module("Cataract");
    rb_define_module_function(module, "parse_css", parse_css, 1);
}
