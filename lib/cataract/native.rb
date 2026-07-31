# frozen_string_literal: true

# Native (C extension) backend for Cataract.
#
# Load this instead of the pure Ruby version by NOT setting CATARACT_PURE
# before requiring 'cataract' (not by requiring this file directly -
# lib/cataract.rb is what sets up Cataract::Backends.active and the
# top-level identity constants like IMPLEMENTATION; this file alone does
# not):
#   require 'cataract'

require_relative 'error'
require_relative 'version'
require_relative 'constants'

# Load struct definitions first (before the C extension) - the extension's
# Init function looks these up and raises if they're missing.
require_relative 'declaration'
require_relative 'rule'
require_relative 'at_rule'
require_relative 'media_query'
require_relative 'conditional_group'
require_relative 'import_statement'

require_relative 'native_extension'

# Load supporting Ruby files (used by both implementations)
require_relative 'stylesheet_scope'
require_relative 'stylesheet'
require_relative 'declarations'

# import_resolver is required on entry to Stylesheet#load_uri and
# #resolve_imports rather than here - see the note in pure.rb.
