#!/usr/bin/env ruby
# frozen_string_literal: true

# Fuzzer worker process - runs in subprocess and parses CSS inputs from stdin
# Communicates via length-prefixed protocol

# Load pure Ruby or C extension based on ENV var
PURE_RUBY = ENV['CATARACT_PURE'] == '1'
if PURE_RUBY
  require_relative '../../lib/cataract/pure'
  COLOR_AVAILABLE = false
else
  require 'cataract'
  require 'cataract/color_conversion'
  COLOR_AVAILABLE = true
end

# Configure aggressive GC to help identify memory leaks (CRuby only)
if RUBY_ENGINE == 'ruby'
  # Disable auto_compact - it can cause issues with C extensions holding pointers
  GC.auto_compact = false
  GC.config(
    malloc_limit: 1_000_000,
    malloc_limit_growth_factor: 1.1,   # Grow very slowly
    oldmalloc_limit_growth_factor: 1.1 # Grow very slowly
  )
end

# Enable GC.stress mode if requested (VERY slow, but makes GC bugs reproducible)
# Only available on CRuby
if ENV['FUZZ_GC_STRESS'] == '1' && RUBY_ENGINE == 'ruby'
  GC.stress = true
  warn '[Worker] GC.stress enabled - expect 100-1000x slowdown'
end

# Enable debug logging if requested
if ENV['FUZZ_DEBUG'] == '1'
  warn '[Worker] Debug logging enabled'
end

COLOR_FORMATS = %i[hex rgb hsl hwb oklab oklch lab lch].freeze

# In-memory import fetcher - same as in run.rb
# Returns CSS from constant hash instead of reading files
IMPORT_CSS_FILES = {
  'base.css' => '.imported { color: blue; margin: 10px; }',
  'responsive.css' => '@media screen and (min-width: 768px) { .responsive { display: flex; } }',
  'parent.css' => "@import 'child.css';\n.parent { padding: 5px; }",
  'child.css' => '.child { font-size: 14px; }',
  'charset.css' => '@charset "UTF-8"; .unicode { content: "★"; }',
  'nested.css' => '.outer { color: red; .inner { color: blue; } }',
  'multi.css' => '.one { color: red; } .two { color: blue; } .three { color: green; }'
}.freeze

InMemoryImportFetcher = lambda do |url, _opts|
  filename = url.split('/').last || 'base.css'
  IMPORT_CSS_FILES[filename] || IMPORT_CSS_FILES['base.css']
end

# Read length-prefixed inputs and parse them
loop do
  # Read 4-byte length prefix (network byte order)
  len_bytes = $stdin.read(4)
  break if len_bytes.nil? || len_bytes.bytesize != 4

  length = len_bytes.unpack1('N')

  # Read CSS input
  css = $stdin.read(length)
  break if css.nil? || css.bytesize != length

  # Parse CSS (crash will kill subprocess)
  # Enable import resolution with in-memory fetcher to exercise that code path
  # Enable URL conversion to exercise convert_urls_in_value code path
  # Enable parse error detection to exercise error checking code paths
  begin
    # Silence warnings during parsing to avoid stderr buffer issues in subprocess
    old_verbose = $VERBOSE
    $VERBOSE = nil
    stylesheet = Cataract.parse_css(css,
                                    import: {
                                      fetcher: InMemoryImportFetcher,
                                      allowed_schemes: %w[http https file], # Allow any scheme
                                      max_depth: 5 # Limit recursion to avoid infinite loops in fuzzing
                                    },
                                    base_uri: 'http://example.com/css/main.css',
                                    absolute_paths: true,
                                    raise_parse_errors: true)
    $VERBOSE = old_verbose
    rules = stylesheet.rules.to_a
    flatten_tested = false
    to_s_tested = false
    color_converted = false

    # Test flatten with valid CSS followed by fuzzed CSS
    # This tests flatten error handling when second rule set is invalid
    begin
      valid_stylesheet = Cataract.parse_css('body { margin: 0; color: red; }',
                                            raise_parse_errors: true)
      valid_stylesheet.add_block(css) # Add fuzzed CSS to valid stylesheet (inherits raise_parse_errors from parent)
      valid_stylesheet.flatten # Call flatten on the stylesheet
      flatten_tested = true
    rescue Cataract::ParseError
      # ParseError should bubble up to outer rescue for tracking
      raise
    rescue Cataract::Error
      # Other errors (flatten errors, etc) - expected and can be ignored
    end

    # Test to_s on parsed rules occasionally
    # This tests serialization on fuzzed data
    if !rules.empty? && rand < 0.01
      stylesheet.to_s
      to_s_tested = true
    end

    if !rules.empty? && rand < 0.02
      stylesheet.to_formatted_s
      to_s_tested = true
    end

    # Test color conversion occasionally (10% chance)
    # This tests color parsing/conversion on fuzzed color values
    # Only available in C extension mode
    if COLOR_AVAILABLE && rand < 0.1
      begin
        # Try random color format conversions
        from_format = COLOR_FORMATS.sample
        to_format = COLOR_FORMATS.sample
        stylesheet.convert_colors!(from: from_format, to: to_format)
        color_converted = true
      rescue Cataract::Error, ArgumentError
        # Expected - color conversion might fail on invalid colors
      end
    end

    # Report what was tested: PARSE [+MERGE] [+TOS] [+COLOR]
    output = 'PARSE'
    output += '+FLATTEN' if flatten_tested
    output += '+TOS' if to_s_tested
    output += '+COLOR' if color_converted
    $stdout.write("#{output}\n")
  rescue Cataract::ParseError
    # Expected - parse errors should be caught gracefully
    $VERBOSE = old_verbose if defined?(old_verbose)
    $stdout.write("PARSE_ERR\n")
  rescue Cataract::DepthError
    $VERBOSE = old_verbose if defined?(old_verbose)
    $stdout.write("DEPTH\n")
  rescue Cataract::SizeError
    $VERBOSE = old_verbose if defined?(old_verbose)
    $stdout.write("SIZE\n")
  rescue StandardError => e
    $VERBOSE = old_verbose if defined?(old_verbose)
    # Always log errors to a file for debugging
    File.open(File.join(__dir__, 'fuzz_errors.log'), 'a') do |f|
      f.puts "[#{Time.now}] #{e.class}: #{e.message}"
      f.puts e.backtrace.first(5).join("\n") if e.backtrace
      f.puts '---'
    end
    # Log errors to stderr if FUZZ_DEBUG is enabled
    if ENV['FUZZ_DEBUG'] == '1'
      $stderr.puts "[Worker Error] #{e.class}: #{e.message}"
      $stderr.puts e.backtrace.first(3).join("\n") if e.backtrace
    end
    $stdout.write("ERR\n")
  end

  $stdout.flush
end
