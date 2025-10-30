#!/usr/bin/env ruby
# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/cataract'
require 'tmpdir'
require 'webmock/minitest'

class TestImports < Minitest::Test
  def setup
    @parser = Cataract::Parser.new
  end

  # ============================================================================
  # imports: false (default) - @import is treated as a regular rule
  # ============================================================================

  def test_import_disabled_by_default
    css = '@import url("https://example.com/style.css");
body { color: red; }'
    @parser.parse(css)

    # @import is ignored when imports are disabled (per CSS spec, @import is a directive not a rule)
    # Only body rule should be parsed
    assert_equal 1, @parser.rules_count

    selectors = []
    @parser.each_selector { |sel, _, _, _| selectors << sel }

    assert_equal ['body'], selectors
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
        @parser.parse(css, imports: true)
      end
    end
  end

  def test_import_with_non_css_extension_rejected_by_default
    css = '@import url("https://example.com/malicious.txt");
body { color: red; }'

    # With safe defaults, non-.css extensions should be rejected
    assert_raises(Cataract::ImportError) do
      @parser.parse(css, imports: true)
    end
  end

  def test_import_with_https_url_safe_defaults
    # HTTPS with safe defaults should work
    stub_request(:get, 'https://example.com/style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("https://example.com/style.css");
body { color: red; }'

    @parser.parse(css, imports: true)

    assert_equal 2, @parser.rules_count

    selectors = []
    @parser.each_selector { |sel, _, _, _| selectors << sel }

    assert_includes selectors, '.imported'
    assert_includes selectors, 'body'
  end

  def test_import_with_http_url_rejected_by_default
    # HTTP should be rejected with safe defaults
    stub_request(:get, 'http://example.com/style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("http://example.com/style.css");'

    assert_raises(Cataract::ImportError) do
      @parser.parse(css, imports: true)
    end
  end

  def test_import_with_http_url_when_allowed
    # HTTP should work when explicitly allowed
    stub_request(:get, 'http://example.com/style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("http://example.com/style.css");'

    @parser.parse(css, imports: { allowed_schemes: ['http'] })

    assert_equal 1, @parser.rules_count
  end

  def test_import_with_nested_https_imports
    # Main file imports level1.css via HTTPS
    stub_request(:get, 'https://example.com/level1.css')
      .to_return(status: 200, body: '@import url("https://example.com/level2.css"); .level1 { color: red; }')

    stub_request(:get, 'https://example.com/level2.css')
      .to_return(status: 200, body: '.level2 { color: blue; }')

    css = '@import url("https://example.com/level1.css");'

    @parser.parse(css, imports: true)

    assert_equal 2, @parser.rules_count

    selectors = []
    @parser.each_selector { |sel, _, _, _| selectors << sel }

    assert_includes selectors, '.level1'
    assert_includes selectors, '.level2'
  end

  def test_import_http_404_error
    stub_request(:get, 'https://example.com/missing.css')
      .to_return(status: 404, body: 'Not Found')

    css = '@import url("https://example.com/missing.css");'

    assert_raises(Cataract::ImportError) do
      @parser.parse(css, imports: true)
    end
  end

  def test_import_http_network_timeout
    stub_request(:get, 'https://slow.example.com/style.css')
      .to_timeout

    css = '@import url("https://slow.example.com/style.css");'

    assert_raises(Cataract::ImportError) do
      @parser.parse(css, imports: { timeout: 1 })
    end
  end

  def test_import_http_redirect_followed
    stub_request(:get, 'https://example.com/style.css')
      .to_return(status: 301, headers: { 'Location' => 'https://example.com/new-style.css' })

    stub_request(:get, 'https://example.com/new-style.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import url("https://example.com/style.css");'

    @parser.parse(css, imports: { follow_redirects: true })

    assert_equal 1, @parser.rules_count

    selectors = []
    @parser.each_selector { |sel, _, _, _| selectors << sel }

    assert_includes selectors, '.imported'
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

      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      # Should have both imported rule and body rule
      assert_equal 2, @parser.rules_count

      selectors = []
      @parser.each_selector { |sel, _, _, _| selectors << sel }

      assert_includes selectors, '.imported'
      assert_includes selectors, 'body'
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
        @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'], max_depth: 2 })
      end

      # With max_depth: 3, should succeed
      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'], max_depth: 3 })

      assert_equal 3, @parser.rules_count
    end
  end

  def test_import_with_custom_extensions
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'styles.txt')
      File.write(imported_file, '.from-txt { color: blue; }')

      css = "@import url('file://#{imported_file}');"

      # Should work with custom extensions
      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['txt'] })

      selectors = []
      @parser.each_selector { |sel, _, _, _| selectors << sel }

      assert_includes selectors, '.from-txt'
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
        @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

        selectors = []
        @parser.each_selector { |sel, _, _, _| selectors << sel }

        assert_includes selectors, '.imported'
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
      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      selectors = []
      @parser.each_selector { |sel, _, _, _| selectors << sel }

      assert_includes selectors, '.imported'
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
      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_equal 1, @parser.rules_count
    end
  end

  def test_import_with_string_literal
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      css = "@import 'file://#{imported_file}';"
      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_equal 1, @parser.rules_count
    end
  end

  def test_import_with_media_query
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'print.css')
      File.write(imported_file, '.print-only { color: blue; }')

      css = "@import url('file://#{imported_file}') print;"
      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      # Should import with print media type
      assert_equal 1, @parser.rules_count

      print_rules = []
      @parser.each_selector(:print) { |sel, _, _, _| print_rules << sel }

      assert_includes print_rules, '.print-only'
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

      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      assert_equal 3, @parser.rules_count

      selectors = []
      @parser.each_selector { |sel, _, _, _| selectors << sel }

      assert_includes selectors, '*'
      assert_includes selectors, 'body'
      assert_includes selectors, '.main'
    end
  end

  # ============================================================================
  # Error handling
  # ============================================================================

  def test_import_missing_file
    css = "@import url('file:///nonexistent/path/to/file.css');"

    assert_raises(Cataract::ImportError) do
      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })
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
        @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'], max_depth: 10 })
      end
    end
  end

  def test_import_preserves_charset
    Dir.mktmpdir do |dir|
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '@charset "UTF-8"; .imported { content: "★"; }')

      css = "@import url('file://#{imported_file}');
body { color: red; }"

      @parser.parse(css, imports: { allowed_schemes: ['file'], extensions: ['css'] })

      # Main file should preserve charset from import
      # (Note: per CSS spec, only first @charset is used)
      assert_equal 'UTF-8', @parser.instance_variable_get(:@charset)
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

      selectors = []
      sheet.each_selector { |sel, _, _, _| selectors << sel }

      assert_includes selectors, '.imported'
      assert_includes selectors, 'body'
    end
  end
end
