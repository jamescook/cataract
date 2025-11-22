# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'webmock/minitest'

class TestImports < Minitest::Test
  # Helper class for testing custom fetcher with state
  class CachingFetcher
    attr_reader :fetch_count

    def initialize
      @cache = {}
      @fetch_count = 0
    end

    def call(url, _opts)
      @fetch_count += 1
      @cache[url] ||= ".cached-#{@fetch_count} { content: '#{url}'; }"
    end
  end

  # ============================================================================
  # import: false (default) - @import is treated as a regular rule
  # ============================================================================

  # ============================================================================
  # import: true (safe defaults)
  # ============================================================================

  def test_import_with_file_scheme_rejected_by_default
    # Create a temp CSS file
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      css = "@import url('file://#{imported_file}');
body { color: red; }"

      # With safe defaults, file:// should be rejected
      assert_raises(Cataract::ImportError) do
        Cataract.parse_css(css, import: true)
      end
    end
  end

  def test_import_with_non_css_extension_rejected_by_default
    css = '@import url("https://example.com/malicious.txt");
body { color: red; }'

    # With safe defaults, non-.css extensions should be rejected
    assert_raises(Cataract::ImportError) do
      Cataract.parse_css(css, import: true)
    end
  end

  def test_import_with_https_url_safe_defaults
    # HTTPS with safe defaults should work
    stub_request(:get, 'https://example.com/style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("https://example.com/style.css");
body { color: red; }'

    sheet = Cataract.parse_css(css, import: true)

    assert_equal 2, sheet.size

    assert_has_selector '.imported', sheet
    assert_has_selector 'body', sheet
  end

  def test_import_with_http_url_rejected_by_default
    # HTTP should be rejected with safe defaults
    stub_request(:get, 'http://example.com/style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("http://example.com/style.css");'

    assert_raises(Cataract::ImportError) do
      Cataract.parse_css(css, import: true)
    end
  end

  def test_import_with_http_url_when_allowed
    # HTTP should work when explicitly allowed
    stub_request(:get, 'http://example.com/style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("http://example.com/style.css");'

    sheet = Cataract.parse_css(css, import: { allowed_schemes: ['http'] })

    assert_equal 1, sheet.size
  end

  def test_import_with_nested_https_imports
    # Main file imports level1.css via HTTPS
    stub_request(:get, 'https://example.com/level1.css')
      .to_return(status: 200, body: '@import url("https://example.com/level2.css"); .level1 { color: red; }')

    stub_request(:get, 'https://example.com/level2.css')
      .to_return(status: 200, body: '.level2 { color: blue; }')

    css = '@import url("https://example.com/level1.css");'

    sheet = Cataract.parse_css(css, import: true)

    assert_equal 2, sheet.size

    assert_has_selector '.level1', sheet
    assert_has_selector '.level2', sheet
  end

  def test_import_http_404_error
    stub_request(:get, 'https://example.com/missing.css')
      .to_return(status: 404, body: 'Not Found')

    css = '@import url("https://example.com/missing.css");'

    assert_raises(Cataract::ImportError) do
      Cataract.parse_css(css, import: true)
    end
  end

  def test_import_http_network_timeout
    stub_request(:get, 'https://slow.example.com/style.css')
      .to_timeout

    css = '@import url("https://slow.example.com/style.css");'

    assert_raises(Cataract::ImportError) do
      Cataract.parse_css(css, import: { timeout: 1 })
    end
  end

  def test_import_http_redirect_followed
    stub_request(:get, 'https://example.com/style.css')
      .to_return(status: 301, headers: { 'Location' => 'https://example.com/new-style.css' })

    stub_request(:get, 'https://example.com/new-style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("https://example.com/style.css");'

    sheet = Cataract.parse_css(css, import: { follow_redirects: true })

    assert_equal 1, sheet.size

    assert_has_selector '.imported', sheet
  end

  # ============================================================================
  # import: { ... } (custom options)
  # ============================================================================

  def test_import_with_file_scheme_when_allowed
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      css = "@import url('file://#{imported_file}');
body { color: red; }"

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'] })

      # Should have both imported rule and body rule
      assert_equal 2, sheet.size

      assert_has_selector '.imported', sheet
      assert_has_selector 'body', sheet
    end
  end

  def test_import_with_custom_max_depth
    Dir.mktmpdir do |dir|
      # Create nested import: level1.css -> level2.css -> level3.css
      File.write(File.join(dir, 'level3.css'), '.level3 { color: green; }')
      File.write(File.join(dir, 'level2.css'),
                 "@import url('file://#{File.join(dir, 'level3.css')}'); .level2 { color: blue; }")
      File.write(File.join(dir, 'level1.css'),
                 "@import url('file://#{File.join(dir, 'level2.css')}'); .level1 { color: red; }")

      css = "@import url('file://#{File.join(dir, 'level1.css')}');"

      # With max_depth: 2, should fail on level3
      assert_raises(Cataract::ImportError) do
        Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'], max_depth: 2 })
      end

      # With max_depth: 3, should succeed
      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'], max_depth: 3 })

      assert_equal 3, sheet.size
    end
  end

  def test_import_with_custom_extensions
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'styles.txt')
      File.write(imported_file, '.from-txt { color: blue; }')

      css = "@import url('file://#{imported_file}');"

      # Should work with custom extensions
      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['txt'] })

      assert_has_selector '.from-txt', sheet
    end
  end

  def test_import_with_relative_path
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      # Change to the directory so relative path works
      Dir.chdir(dir) do
        css = "@import 'imported.css';"

        # Relative paths are converted to file:// URLs
        sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'] })

        assert_has_selector '.imported', sheet
      end
    end
  end

  def test_import_with_absolute_path
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      # Use absolute path without file:// scheme
      css = "@import '#{imported_file}';"

      # Absolute paths without scheme are converted to file:// URLs
      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_has_selector '.imported', sheet
    end
  end

  # ============================================================================
  # @import syntax variations
  # ============================================================================

  def test_import_with_url_function
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      css = "@import url('file://#{imported_file}');"
      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_equal 1, sheet.size
    end
  end

  def test_import_with_string_literal
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      css = "@import 'file://#{imported_file}';"
      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_equal 1, sheet.size
    end
  end

  # ============================================================================
  # Multiple imports
  # ============================================================================

  def test_multiple_imports
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'reset.css'), '* { margin: 0; }')
      File.write(File.join(dir, 'theme.css'), 'body { background: white; }')

      css = "@import url('file://#{File.join(dir, 'reset.css')}');
@import url('file://#{File.join(dir, 'theme.css')}');
.main { padding: 10px; }"

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_equal 3, sheet.size

      assert_has_selector '*', sheet
      assert_has_selector 'body', sheet
      assert_has_selector '.main', sheet
    end
  end

  # ============================================================================
  # Error handling
  # ============================================================================

  def test_import_missing_file
    css = "@import url('file:///nonexistent/path/to/file.css');"

    assert_raises(Cataract::ImportError) do
      Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'] })
    end
  end

  def test_import_circular_reference
    Dir.mktmpdir do |dir|
      file_a = File.join(dir, 'a.css')
      file_b = File.join(dir, 'b.css')

      File.write(file_a, "@import url('file://#{file_b}'); .a { color: red; }")
      File.write(file_b, "@import url('file://#{file_a}'); .b { color: blue; }")

      css = "@import url('file://#{file_a}');"

      assert_raises(Cataract::ImportError) do
        Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'], max_depth: 10 })
      end
    end
  end

  def test_import_preserves_charset
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '@charset "UTF-8"; .imported { content: "★"; }')

      css = "@import url('file://#{imported_file}');
body { color: red; }"

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'] })

      # Main file should preserve charset from import
      # (Note: per CSS spec, only first @charset is used)
      assert_equal 'UTF-8', sheet.charset
    end
  end

  # ============================================================================
  # Stylesheet API
  # ============================================================================

  def test_stylesheet_parse_with_imports
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      css = "@import url('file://#{imported_file}');
body { color: red; }"

      # Cataract.parse_css should also support imports
      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_equal 2, sheet.size

      assert_has_selector '.imported', sheet
      assert_has_selector 'body', sheet
    end
  end

  # ============================================================================
  # base_path option for resolving relative imports
  # ============================================================================

  def test_relative_import_with_base_path
    # Create a directory structure with CSS files
    Dir.mktmpdir do |dir|
      # Create subdirectory
      subdir = File.join(dir, 'styles')
      Dir.mkdir(subdir)

      # Create imported file in subdirectory
      imported_file = File.join(subdir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      # CSS with relative import
      css = "@import 'imported.css';\nbody { color: red; }"

      # Parse with base_path pointing to subdirectory
      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'], base_path: subdir })

      assert_equal 2, sheet.size

      assert_has_selector '.imported', sheet
      assert_has_selector 'body', sheet
    end
  end

  def test_relative_import_without_base_path_fails
    # Create a directory structure with CSS files
    Dir.mktmpdir do |dir|
      subdir = File.join(dir, 'styles')
      Dir.mkdir(subdir)

      # Create imported file in subdirectory (not in cwd)
      imported_file = File.join(subdir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      # CSS with relative import
      css = "@import 'imported.css';\nbody { color: red; }"

      # Parse without base_path - should fail because 'imported.css' doesn't exist in cwd
      assert_raises(Cataract::ImportError) do
        Cataract.parse_css(css, import: { allowed_schemes: ['file'] })
      end
    end
  end

  def test_stylesheet_load_file_sets_base_path_automatically
    # Create a directory structure with CSS files
    Dir.mktmpdir do |dir|
      # Create main CSS file
      main_file = File.join(dir, 'main.css')
      File.write(main_file, "@import 'imported.css';\nbody { color: red; }")

      # Create imported file in same directory
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      # Use Stylesheet.load_file which should automatically set base_path
      sheet = Cataract::Stylesheet.new(import: { allowed_schemes: ['file'] })
      sheet.load_file(main_file)

      assert_equal 2, sheet.size

      assert_has_selector '.imported', sheet
      assert_has_selector 'body', sheet
    end
  end

  def test_import_with_comment_before_import
    # Test that comments before @import are handled correctly
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      # CSS with comment before @import
      css = "/* This is a comment */\n@import url('file://#{imported_file}');\nbody { color: red; }"

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'] })

      assert_equal 2, sheet.size

      assert_has_selector '.imported', sheet
      assert_has_selector 'body', sheet
    end
  end

  def test_import_with_comments_between_imports
    # Test comment skipping while iterating through @import statements
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'first.css'), '.first { color: red; }')
      File.write(File.join(dir, 'second.css'), '.second { color: blue; }')

      # CSS with comments between @import statements
      css = <<~CSS
        @import url('file://#{File.join(dir, 'first.css')}');
        /* Comment between imports */
        /* Another comment
           spanning multiple lines */
        @import url('file://#{File.join(dir, 'second.css')}');
        body { margin: 0; }
      CSS

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'] })

      assert_equal 3, sheet.size

      assert_has_selector '.first', sheet
      assert_has_selector '.second', sheet
      assert_has_selector 'body', sheet
    end
  end

  def test_stylesheet_load_uri_with_file_scheme_sets_base_path
    # Test that load_uri with file:// scheme sets base_path for resolving relative imports
    Dir.mktmpdir do |dir|
      # Create main CSS file with relative @import
      main_file = File.join(dir, 'main.css')
      File.write(main_file, "@import 'imported.css';\nbody { color: red; }")

      # Create imported file in same directory
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      # Use load_uri with file:// scheme - should resolve relative imports
      sheet = Cataract::Stylesheet.new(import: { allowed_schemes: ['file'] })
      sheet.load_uri("file://#{main_file}")

      assert_equal 2, sheet.size

      assert_has_selector '.imported', sheet
      assert_has_selector 'body', sheet
    end
  end

  # ============================================================================
  # Custom fetcher API
  # ============================================================================

  def test_custom_fetcher_with_lambda
    # Create a simple lambda fetcher that returns mock CSS
    custom_fetcher = lambda do |url, _opts|
      case url
      when 'https://example.com/custom.css'
        '.custom { color: purple; }'
      else
        raise Cataract::ImportError, "Unknown URL: #{url}"
      end
    end

    css = "@import url('https://example.com/custom.css');\nbody { color: red; }"

    sheet = Cataract.parse_css(css, import: { fetcher: custom_fetcher })

    assert_equal 2, sheet.size
    assert_has_selector '.custom', sheet
    assert_has_selector 'body', sheet
  end

  def test_custom_fetcher_with_callable_object
    # Test using the CachingFetcher helper class defined above
    fetcher = CachingFetcher.new

    css = "@import url('https://example.com/styles.css');\nbody { color: red; }"

    sheet = Cataract.parse_css(css, import: { fetcher: fetcher })

    assert_equal 2, sheet.size
    assert_equal 1, fetcher.fetch_count
  end

  def test_custom_fetcher_with_nested_imports
    # Test that custom fetcher is passed through recursive imports
    fetch_log = []

    custom_fetcher = lambda do |url, _opts|
      fetch_log << url
      case url
      when 'https://example.com/level1.css'
        "@import url('https://example.com/level2.css'); .level1 { color: red; }"
      when 'https://example.com/level2.css'
        '.level2 { color: blue; }'
      else
        raise Cataract::ImportError, "Unknown URL: #{url}"
      end
    end

    css = "@import url('https://example.com/level1.css');"

    sheet = Cataract.parse_css(css, import: { fetcher: custom_fetcher })

    assert_equal 2, sheet.size
    assert_equal ['https://example.com/level1.css', 'https://example.com/level2.css'], fetch_log
    assert_has_selector '.level1', sheet
    assert_has_selector '.level2', sheet
  end

  def test_custom_fetcher_receives_options
    # Test that fetcher receives the full options hash
    received_options = nil

    custom_fetcher = lambda do |_url, opts|
      received_options = opts
      '.test { color: green; }'
    end

    css = "@import url('https://example.com/test.css');"

    Cataract.parse_css(css, import: {
                         fetcher: custom_fetcher,
                         max_depth: 10,
                         allowed_schemes: ['https'],
                         timeout: 30
                       })

    refute_nil received_options
    assert_equal 10, received_options[:max_depth]
    assert_equal ['https'], received_options[:allowed_schemes]
    assert_equal 30, received_options[:timeout]
  end

  def test_custom_fetcher_can_raise_import_error
    # Test that custom fetcher can raise ImportError for error handling
    custom_fetcher = lambda do |url, _opts|
      raise Cataract::ImportError, "Custom fetcher: cannot fetch #{url}"
    end

    css = "@import url('https://example.com/error.css');"

    error = assert_raises(Cataract::ImportError) do
      Cataract.parse_css(css, import: { fetcher: custom_fetcher })
    end

    assert_match(/Custom fetcher/, error.message) # rubocop:disable Cataract/BanAssertIncludes
  end

  def test_custom_fetcher_with_media_queries
    # Test that custom fetcher works with @import media queries
    custom_fetcher = lambda do |_url, _opts|
      '.print-styles { page-break-after: always; }'
    end

    css = "@import url('https://example.com/print.css') print;"

    sheet = Cataract.parse_css(css, import: { fetcher: custom_fetcher })

    assert_equal 1, sheet.size
    assert_has_selector '.print-styles', sheet, media: :print
  end

  def test_default_fetcher_still_works_without_explicit_option
    # Test that existing behavior works when no fetcher is specified
    # This should use the DefaultFetcher internally
    stub_request(:get, 'https://example.com/default.css')
      .to_return(status: 200, body: '.default { color: orange; }')

    css = '@import url("https://example.com/default.css");'

    sheet = Cataract.parse_css(css, import: true)

    assert_equal 1, sheet.size
    assert_has_selector '.default', sheet
  end

  def test_custom_fetcher_for_browser_simulation
    # Simulate a browser-compatible fetcher (synchronous, no file access)
    browser_fetcher = lambda do |url, _opts|
      # In real Opal, this would call JavaScript fetch() via Native
      # For this test, we just simulate the behavior

      uri = URI.parse(url)

      # Browser can't access file:// in typical scenarios
      if uri.scheme == 'file'
        raise Cataract::ImportError, 'Browser cannot access file:// URLs'
      end

      # Simulate fetching from network
      case url
      when 'https://cdn.example.com/reset.css'
        '* { margin: 0; padding: 0; }'
      when 'https://cdn.example.com/theme.css'
        'body { font-family: sans-serif; }'
      else
        raise Cataract::ImportError, "Network error: could not fetch #{url}"
      end
    end

    css = <<~CSS
      @import url('https://cdn.example.com/reset.css');
      @import url('https://cdn.example.com/theme.css');
      .app { padding: 20px; }
    CSS

    sheet = Cataract.parse_css(css, import: { fetcher: browser_fetcher })

    assert_equal 3, sheet.size
    assert_has_selector '*', sheet
    assert_has_selector 'body', sheet
    assert_has_selector '.app', sheet
  end

  def test_custom_fetcher_for_user_provided_imports
    # Simulate a scenario where user provides all imports upfront
    # (useful for interactive browser tools)
    user_provided_imports = {
      'https://example.com/vars.css' => ':root { --primary: blue; }',
      'https://example.com/buttons.css' => 'button { background: var(--primary); }'
    }

    static_fetcher = lambda do |url, _opts|
      user_provided_imports.fetch(url) do
        raise Cataract::ImportError, "Import not provided by user: #{url}"
      end
    end

    css = <<~CSS
      @import url('https://example.com/vars.css');
      @import url('https://example.com/buttons.css');
      .main { color: black; }
    CSS

    sheet = Cataract.parse_css(css, import: { fetcher: static_fetcher })

    assert_equal 3, sheet.size
    assert_has_selector ':root', sheet
    assert_has_selector 'button', sheet
    assert_has_selector '.main', sheet
  end

  # ============================================================================
  # @import position validation (CSS spec compliance)
  # ============================================================================

  def test_import_at_bottom_should_be_ignored
    # Per CSS spec: @import after any rules should be invalid/ignored
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'imported.css'), '.imported { color: blue; }')

      css = "body { color: red; }\n@import url('file://#{File.join(dir, 'imported.css')}');"

      warnings = capture_warnings do
        @sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'] })
      end

      # Should only have body rule, @import should be ignored
      assert_equal 1, @sheet.size
      assert_has_selector 'body', @sheet
      refute_includes @sheet.selectors, '.imported', '@import after rules should be ignored'

      # Should emit a warning about @import after rules
      assert_equal 1, warnings.length
      assert_match(/CSS @import ignored.*must appear before all rules/i, warnings.first) # rubocop:disable Cataract/BanAssertIncludes
    end
  end

  def test_import_in_middle_should_be_ignored
    # Per CSS spec: @import must come before all rules except @charset
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'first.css'), '.first { color: red; }')
      File.write(File.join(dir, 'second.css'), '.second { color: blue; }')

      css = "@import url('file://#{File.join(dir, 'first.css')}');\nbody { color: green; }\n@import url('file://#{File.join(dir, 'second.css')}');\ndiv { margin: 0; }"

      warnings = capture_warnings do
        @sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'] })
      end

      # Should have: .first (from valid import), body
      # The invalid @import and subsequent rules get parsed as malformed at-rule
      # This is current behavior - not ideal but spec-compliant (invalid @import is ignored)
      assert_operator @sheet.size, :>=, 2, 'Should have at least .first and body rules'
      assert_has_selector '.first', @sheet
      assert_has_selector 'body', @sheet
      refute_includes @sheet.selectors, '.second', 'Second import content should not be loaded'

      # Should emit a warning about the second @import after rules
      assert_equal 1, warnings.length
      assert_match(/CSS @import ignored.*must appear before all rules/i, warnings.first) # rubocop:disable Cataract/BanAssertIncludes
    end
  end

  def test_multiple_imports_at_top_correct_order
    # Per CSS spec: Multiple @imports at top should all be processed in order
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'reset.css'), '* { margin: 0; }')
      File.write(File.join(dir, 'theme.css'), 'body { background: white; }')
      File.write(File.join(dir, 'layout.css'), 'div { display: block; }')

      css = "@import url('file://#{File.join(dir, 'reset.css')}');\n@import url('file://#{File.join(dir, 'theme.css')}');\n@import url('file://#{File.join(dir, 'layout.css')}');\n.main { padding: 10px; }"

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'] })

      # All imports should be processed, in order
      assert_equal 4, sheet.size

      # Check order: imports first, then .main
      selectors = sheet.map(&:selector)

      assert_equal '*', selectors[0], 'First import should be first'
      assert_equal 'body', selectors[1], 'Second import should be second'
      assert_equal 'div', selectors[2], 'Third import should be third'
      assert_equal '.main', selectors[3], 'Local rule should be last'
    end
  end

  def test_import_after_charset_is_valid
    # skip 'TODO: ImportResolver needs refactoring to preserve @charset at top'
    # Per CSS spec: @import can come after @charset
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'imported.css'), '.imported { color: blue; }')

      css = "@charset \"UTF-8\";\n@import url('file://#{File.join(dir, 'imported.css')}');\nbody { color: red; }"

      sheet = Cataract.parse_css(css, import: { allowed_schemes: ['file'] })

      # Should have both imported and body rules
      assert_equal 2, sheet.size
      assert_has_selector '.imported', sheet
      assert_has_selector 'body', sheet
    end
  end

  def test_recursive_imports_correct_order
    # Test that deeply nested imports are resolved in correct order
    # base.css -> file1.css -> file2.css -> file3.css
    # Each file has its own CSS rules to verify ordering
    Dir.mktmpdir do |dir|
      # Deepest level (file3.css) - no imports, just rules
      File.write(File.join(dir, 'file3.css'), ".level3 { color: purple; }\n.level3-extra { margin: 3px; }")

      # Middle level (file2.css) - imports file3, has own rules
      File.write(File.join(dir, 'file2.css'), "@import url('file://#{File.join(dir, 'file3.css')}');\n.level2 { color: blue; }\n.level2-extra { margin: 2px; }")

      # First level (file1.css) - imports file2, has own rules
      File.write(File.join(dir, 'file1.css'), "@import url('file://#{File.join(dir, 'file2.css')}');\n.level1 { color: green; }\n.level1-extra { margin: 1px; }")

      # Base CSS - imports file1, has own rules
      base_css = "@import url('file://#{File.join(dir, 'file1.css')}');\n.base { color: red; }\n.base-extra { margin: 0; }"

      sheet = Cataract.parse_css(base_css, import: { allowed_schemes: ['file'] })

      # Should have all 8 rules
      assert_equal 8, sheet.size

      # Check exact order:
      # 1. file3 rules (deepest import, processed first in the chain)
      # 2. file2 rules (imports file3, then its own rules)
      # 3. file1 rules (imports file2, then its own rules)
      # 4. base rules (imports file1, then its own rules)
      selectors = sheet.map(&:selector)

      assert_equal '.level3', selectors[0], 'Deepest import rule 1 should be first'
      assert_equal '.level3-extra', selectors[1], 'Deepest import rule 2 should be second'
      assert_equal '.level2', selectors[2], 'Second level rule 1 should be third'
      assert_equal '.level2-extra', selectors[3], 'Second level rule 2 should be fourth'
      assert_equal '.level1', selectors[4], 'First level rule 1 should be fifth'
      assert_equal '.level1-extra', selectors[5], 'First level rule 2 should be sixth'
      assert_equal '.base', selectors[6], 'Base rule 1 should be seventh'
      assert_equal '.base-extra', selectors[7], 'Base rule 2 should be eighth'
    end
  end

  def test_single_import_resolution
    Dir.mktmpdir do |dir|
      # Create imported file
      File.write(File.join(dir, 'base.css'), '.base { color: blue; }')

      # Main CSS with import
      css = "@import url('file://#{File.join(dir, 'base.css')}');\nbody { color: red; }"

      sheet = Cataract::Stylesheet.parse(css, import: { allowed_schemes: ['file'] })

      # After resolution, should have both rules
      assert_equal 2, sheet.size, 'Should have imported rule + local rule'

      # Import should be kept but marked as resolved
      assert_equal 1, sheet.imports.length, 'Import should be retained'
      assert sheet.imports[0].resolved, 'Import should be marked as resolved'

      # Check rule order: imported rules first, then local rules
      assert_equal '.base', sheet.rules[0].selector
      assert_equal 'body', sheet.rules[1].selector
    end
  end

  def test_multiple_imports_resolution_order
    Dir.mktmpdir do |dir|
      # Create multiple imported files
      File.write(File.join(dir, 'reset.css'), '* { margin: 0; }')
      File.write(File.join(dir, 'theme.css'), 'body { background: white; }')
      File.write(File.join(dir, 'layout.css'), 'div { display: block; }')

      css = <<~CSS
        @import url('file://#{File.join(dir, 'reset.css')}');
        @import url('file://#{File.join(dir, 'theme.css')}');
        @import url('file://#{File.join(dir, 'layout.css')}');
        .main { padding: 10px; }
      CSS

      sheet = Cataract::Stylesheet.parse(css, import: { allowed_schemes: ['file'] })

      assert_equal 4, sheet.size
      assert_equal 3, sheet.imports.length, 'All 3 imports should be retained'

      # All imports should be marked resolved
      sheet.imports.each do |import|
        assert import.resolved, "Import #{import.url} should be resolved"
      end

      # Check order: imports in order encountered, then local rules
      selectors = sheet.rules.map(&:selector)

      assert_equal '*', selectors[0], 'First import should be first'
      assert_equal 'body', selectors[1], 'Second import should be second'
      assert_equal 'div', selectors[2], 'Third import should be third'
      assert_equal '.main', selectors[3], 'Local rule should be last'
    end
  end

  def test_recursive_import_resolution
    Dir.mktmpdir do |dir|
      # Create a chain: main -> level1 -> level2 -> level3
      File.write(File.join(dir, 'level3.css'), '.level3 { color: purple; }')

      File.write(File.join(dir, 'level2.css'), <<~CSS)
        @import url('file://#{File.join(dir, 'level3.css')}');
        .level2 { color: blue; }
      CSS

      File.write(File.join(dir, 'level1.css'), <<~CSS)
        @import url('file://#{File.join(dir, 'level2.css')}');
        .level1 { color: green; }
      CSS

      main_css = <<~CSS
        @import url('file://#{File.join(dir, 'level1.css')}');
        .main { color: red; }
      CSS

      sheet = Cataract::Stylesheet.parse(main_css, import: { allowed_schemes: ['file'] })

      assert_equal 4, sheet.size

      # Only the top-level import should be in the imports array
      # Nested imports are resolved recursively but not added to main stylesheet's imports
      assert_equal 1, sheet.imports.length
      assert sheet.imports[0].resolved

      # Order should be: level3, level2, level1, main (depth-first)
      selectors = sheet.rules.map(&:selector)

      assert_equal '.level3', selectors[0], 'Deepest import first'
      assert_equal '.level2', selectors[1]
      assert_equal '.level1', selectors[2]
      assert_equal '.main', selectors[3], 'Main rules last'
    end
  end

  def test_import_with_media_query
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'print.css'), '.print-only { display: none; }')

      css = "@import url('file://#{File.join(dir, 'print.css')}') print;\nbody { color: red; }"

      sheet = Cataract::Stylesheet.parse(css, import: { allowed_schemes: ['file'] })

      assert_equal 2, sheet.size
      assert_equal 1, sheet.imports.length
      assert sheet.imports[0].resolved

      # Imported rule should have print media
      import_rule = sheet.rules[0]

      assert_equal '.print-only', import_rule.selector
      # Check media via media_index
      assert_matches_media :print, sheet
      print_rules = sheet.with_media(:print)

      assert_member print_rules.map(&:selector), '.print-only'

      # Main rule should have no media (base rules)
      main_rule = sheet.rules[1]

      assert_equal 'body', main_rule.selector
      base_rules = sheet.base_rules

      assert_member base_rules.map(&:selector), 'body'
    end
  end

  def test_import_with_charset_preserved
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'imported.css'), '.imported { color: blue; }')

      css = "@charset \"UTF-8\";\n@import url('file://#{File.join(dir, 'imported.css')}');\nbody { color: red; }"

      sheet = Cataract::Stylesheet.parse(css, import: { allowed_schemes: ['file'] })

      # Charset should be preserved
      assert_equal 'UTF-8', sheet.charset

      # Both rules should exist
      assert_equal 2, sheet.size
      assert_equal '.imported', sheet.rules[0].selector
      assert_equal 'body', sheet.rules[1].selector

      # Import should be resolved
      assert_equal 1, sheet.imports.length
      assert sheet.imports[0].resolved
    end
  end

  def test_circular_import_detection
    Dir.mktmpdir do |dir|
      # Create circular reference: a -> b -> a
      a_path = File.join(dir, 'a.css')
      b_path = File.join(dir, 'b.css')

      File.write(b_path, "@import url('file://#{a_path}');\n.b { color: blue; }")
      File.write(a_path, "@import url('file://#{b_path}');\n.a { color: red; }")

      # Should raise ImportError for circular reference
      assert_raises(Cataract::ImportError) do
        Cataract::Stylesheet.parse(
          "@import url('file://#{a_path}');",
          import: { allowed_schemes: ['file'] }
        )
      end
    end
  end

  def test_import_depth_limit
    Dir.mktmpdir do |dir|
      # Create a deep chain that exceeds max_depth
      prev_file = nil
      10.times do |i|
        file_path = File.join(dir, "level#{i}.css")
        content = ".level#{i} { color: red; }"
        content = "@import url('file://#{prev_file}');\n" + content if prev_file
        File.write(file_path, content)
        prev_file = file_path
      end

      # With max_depth of 5, should raise error
      assert_raises(Cataract::ImportError) do
        Cataract::Stylesheet.parse(
          "@import url('file://#{prev_file}');",
          import: { allowed_schemes: ['file'], max_depth: 5 }
        )
      end
    end
  end

  def test_import_disabled_by_default
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'imported.css'), '.imported { color: blue; }')

      css = "@import url('file://#{File.join(dir, 'imported.css')}');\nbody { color: red; }"

      # Without import option, imports should NOT be resolved
      sheet = Cataract::Stylesheet.parse(css)

      # Import statement should be stored but not resolved
      assert_equal 1, sheet.imports.length
      refute sheet.imports[0].resolved, 'Import should not be resolved when import option is disabled'

      assert_equal 1, sheet.size, 'Should only have local rule'
      assert_equal 'body', sheet.rules[0].selector
    end
  end

  def test_nested_media_queries_in_imports
    Dir.mktmpdir do |dir|
      # Imported file has media query
      File.write(File.join(dir, 'responsive.css'), <<~CSS)
        @media screen and (min-width: 768px) {
          .responsive { width: 100%; }
        }
      CSS

      # Import with its own media query
      css = "@import url('file://#{File.join(dir, 'responsive.css')}') print;"

      sheet = Cataract::Stylesheet.parse(css, import: { allowed_schemes: ['file'] })

      # Rule should have combined media query
      assert_equal 1, sheet.size
      rule = sheet.rules[0]

      assert_equal '.responsive', rule.selector

      # Should combine: "print and screen and (min-width: 768px)" or similar
      # The media_index will have multiple entries (screen, the full nested query, and the combined one)
      media_queries = sheet.media_queries

      # Find a media query that includes both 'print' and 'min-width'
      combined_query = media_queries.find { |mq| mq.to_s.include?('print') && mq.to_s.include?('min-width') }

      refute_nil combined_query, "Should have combined media query with both 'print' and 'min-width', got: #{media_queries.inspect}"
    end
  end

  def test_import_url_extracted_correctly
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'base.css'), '.base { color: blue; }')

      css = "@import url('file://#{File.join(dir, 'base.css')}');"

      sheet = Cataract::Stylesheet.parse(css, import: { allowed_schemes: ['file'] })

      # Import should record the URL
      import = sheet.imports[0]

      assert_equal "file://#{File.join(dir, 'base.css')}", import.url
      assert_nil import.media
      assert import.resolved
    end
  end

  def test_import_media_query_extracted_correctly
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'mobile.css'), '.mobile { width: 100%; }')

      css = "@import url('file://#{File.join(dir, 'mobile.css')}') screen and (max-width: 768px);"

      sheet = Cataract::Stylesheet.parse(css, import: { allowed_schemes: ['file'] })

      # Import should record the media query
      import = sheet.imports[0]

      assert_equal "file://#{File.join(dir, 'mobile.css')}", import.url
      assert_equal 'screen and (max-width: 768px)', import.media
      assert import.resolved
    end
  end
end
