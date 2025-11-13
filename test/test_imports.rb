#!/usr/bin/env ruby
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
  # imports: false (default) - @import is treated as a regular rule
  # ============================================================================

  def test_import_disabled_by_default
    css = '@import url("https://example.com/style.css");
body { color: red; }'
    sheet = Cataract.parse_css(css)

    # @import is ignored when imports are disabled (per CSS spec, @import is a directive not a rule)
    # Only body rule should be parsed
    assert_equal 1, sheet.size

    assert_selectors_match ['body'], sheet
  end

  # ============================================================================
  # imports: true (safe defaults)
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
        Cataract.parse_css(css, imports: true)
      end
    end
  end

  def test_import_with_non_css_extension_rejected_by_default
    css = '@import url("https://example.com/malicious.txt");
body { color: red; }'

    # With safe defaults, non-.css extensions should be rejected
    assert_raises(Cataract::ImportError) do
      Cataract.parse_css(css, imports: true)
    end
  end

  def test_import_with_https_url_safe_defaults
    # HTTPS with safe defaults should work
    stub_request(:get, 'https://example.com/style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("https://example.com/style.css");
body { color: red; }'

    sheet = Cataract.parse_css(css, imports: true)

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
      Cataract.parse_css(css, imports: true)
    end
  end

  def test_import_with_http_url_when_allowed
    # HTTP should work when explicitly allowed
    stub_request(:get, 'http://example.com/style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("http://example.com/style.css");'

    sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['http'] })

    assert_equal 1, sheet.size
  end

  def test_import_with_nested_https_imports
    # Main file imports level1.css via HTTPS
    stub_request(:get, 'https://example.com/level1.css')
      .to_return(status: 200, body: '@import url("https://example.com/level2.css"); .level1 { color: red; }')

    stub_request(:get, 'https://example.com/level2.css')
      .to_return(status: 200, body: '.level2 { color: blue; }')

    css = '@import url("https://example.com/level1.css");'

    sheet = Cataract.parse_css(css, imports: true)

    assert_equal 2, sheet.size

    assert_has_selector '.level1', sheet
    assert_has_selector '.level2', sheet
  end

  def test_import_http_404_error
    stub_request(:get, 'https://example.com/missing.css')
      .to_return(status: 404, body: 'Not Found')

    css = '@import url("https://example.com/missing.css");'

    assert_raises(Cataract::ImportError) do
      Cataract.parse_css(css, imports: true)
    end
  end

  def test_import_http_network_timeout
    stub_request(:get, 'https://slow.example.com/style.css')
      .to_timeout

    css = '@import url("https://slow.example.com/style.css");'

    assert_raises(Cataract::ImportError) do
      Cataract.parse_css(css, imports: { timeout: 1 })
    end
  end

  def test_import_http_redirect_followed
    stub_request(:get, 'https://example.com/style.css')
      .to_return(status: 301, headers: { 'Location' => 'https://example.com/new-style.css' })

    stub_request(:get, 'https://example.com/new-style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("https://example.com/style.css");'

    sheet = Cataract.parse_css(css, imports: { follow_redirects: true })

    assert_equal 1, sheet.size

    assert_has_selector '.imported', sheet
  end

  # ============================================================================
  # imports: { ... } (custom options)
  # ============================================================================

  def test_import_with_file_scheme_when_allowed
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      css = "@import url('file://#{imported_file}');
body { color: red; }"

      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      # Should have both imported rule and body rule
      assert_equal 2, sheet.size

      assert_has_selector '.imported', sheet
      assert_has_selector 'body', sheet
    end
  end

  def test_import_with_custom_max_depth
    Dir.mktmpdir do |dir|
      # Create nested imports: level1.css -> level2.css -> level3.css
      File.write(File.join(dir, 'level3.css'), '.level3 { color: green; }')
      File.write(File.join(dir, 'level2.css'),
                 "@import url('file://#{File.join(dir, 'level3.css')}'); .level2 { color: blue; }")
      File.write(File.join(dir, 'level1.css'),
                 "@import url('file://#{File.join(dir, 'level2.css')}'); .level1 { color: red; }")

      css = "@import url('file://#{File.join(dir, 'level1.css')}');"

      # With max_depth: 2, should fail on level3
      assert_raises(Cataract::ImportError) do
        Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'], max_depth: 2 })
      end

      # With max_depth: 3, should succeed
      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'], max_depth: 3 })

      assert_equal 3, sheet.size
    end
  end

  def test_import_with_custom_extensions
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'styles.txt')
      File.write(imported_file, '.from-txt { color: blue; }')

      css = "@import url('file://#{imported_file}');"

      # Should work with custom extensions
      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['txt'] })

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
        sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

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
      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

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
      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_equal 1, sheet.size
    end
  end

  def test_import_with_string_literal
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      css = "@import 'file://#{imported_file}';"
      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_equal 1, sheet.size
    end
  end

  def test_import_with_media_query
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'print.css')
      File.write(imported_file, '.print-only { color: blue; }')

      css = "@import url('file://#{imported_file}') print;"
      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      # Should import with print media type
      assert_equal 1, sheet.size

      assert_has_selector '.print-only', sheet, media: :print
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

      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

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
      Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })
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
        Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'], max_depth: 10 })
      end
    end
  end

  def test_import_preserves_charset
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '@charset "UTF-8"; .imported { content: "★"; }')

      css = "@import url('file://#{imported_file}');
body { color: red; }"

      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      # Main file should preserve charset from import
      # (Note: per CSS spec, only first @charset is used)
      assert_equal 'UTF-8', sheet.instance_variable_get(:@charset)
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
      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

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
      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'], base_path: subdir })

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
        Cataract.parse_css(css, imports: { allowed_schemes: ['file'] })
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

      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'] })

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

      sheet = Cataract.parse_css(css, imports: { allowed_schemes: ['file'] })

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

    sheet = Cataract.parse_css(css, imports: { fetcher: custom_fetcher })

    assert_equal 2, sheet.size
    assert_has_selector '.custom', sheet
    assert_has_selector 'body', sheet
  end

  def test_custom_fetcher_with_callable_object
    # Test using the CachingFetcher helper class defined above
    fetcher = CachingFetcher.new

    css = "@import url('https://example.com/styles.css');\nbody { color: red; }"

    sheet = Cataract.parse_css(css, imports: { fetcher: fetcher })

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

    sheet = Cataract.parse_css(css, imports: { fetcher: custom_fetcher })

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

    Cataract.parse_css(css, imports: {
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
      Cataract.parse_css(css, imports: { fetcher: custom_fetcher })
    end

    assert_match(/Custom fetcher/, error.message)
  end

  def test_custom_fetcher_with_media_queries
    # Test that custom fetcher works with @import media queries
    custom_fetcher = lambda do |_url, _opts|
      '.print-styles { page-break-after: always; }'
    end

    css = "@import url('https://example.com/print.css') print;"

    sheet = Cataract.parse_css(css, imports: { fetcher: custom_fetcher })

    assert_equal 1, sheet.size
    assert_has_selector '.print-styles', sheet, media: :print
  end

  def test_default_fetcher_still_works_without_explicit_option
    # Test that existing behavior works when no fetcher is specified
    # This should use the DefaultFetcher internally
    stub_request(:get, 'https://example.com/default.css')
      .to_return(status: 200, body: '.default { color: orange; }')

    css = '@import url("https://example.com/default.css");'

    sheet = Cataract.parse_css(css, imports: true)

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

    sheet = Cataract.parse_css(css, imports: { fetcher: browser_fetcher })

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

    sheet = Cataract.parse_css(css, imports: { fetcher: static_fetcher })

    assert_equal 3, sheet.size
    assert_has_selector ':root', sheet
    assert_has_selector 'button', sheet
    assert_has_selector '.main', sheet
  end
end
