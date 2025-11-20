# frozen_string_literal: true

require_relative 'test_helper'
require 'tmpdir'
require 'webmock/minitest'

class TestStylesheetAddBlockOptions < Minitest::Test
  # ============================================================================
  # Constructor defaults for base_uri, base_dir, absolute_paths
  # ============================================================================

  def test_constructor_accepts_base_uri_option
    sheet = Cataract::Stylesheet.new(base_uri: 'https://example.com/css/main.css')

    assert_equal 'https://example.com/css/main.css', sheet.instance_variable_get(:@options)[:base_uri]
  end

  def test_constructor_accepts_base_dir_option
    sheet = Cataract::Stylesheet.new(base_dir: '/var/www/assets/css')

    assert_equal '/var/www/assets/css', sheet.instance_variable_get(:@options)[:base_dir]
  end

  def test_constructor_accepts_absolute_paths_option
    sheet = Cataract::Stylesheet.new(absolute_paths: true)

    assert sheet.instance_variable_get(:@options)[:absolute_paths]
  end

  def test_constructor_defaults_absolute_paths_to_false
    sheet = Cataract::Stylesheet.new

    refute sheet.instance_variable_get(:@options)[:absolute_paths]
  end

  # ============================================================================
  # URL conversion with absolute_paths: true
  # ============================================================================

  def test_convert_uris_basic
    base_uri = 'http://www.example.org/style/basic.css'

    [
      'body { background: url(yellow) };',
      "body { background: url('yellow') };",
      "body { background: url('/style/yellow') };",
      'body { background: url("../style/yellow") };',
      'body { background: url("lib/../../style/yellow") };'
    ].each do |css|
      sheet = Cataract::Stylesheet.new(absolute_paths: true, base_uri: base_uri)
      sheet.add_block(css)

      rule = sheet.rules.first

      assert_has_property({ background: "url('http://www.example.org/style/yellow')" }, rule,
                          "Failed for input: #{css}")
    end
  end

  def test_convert_uris_with_query_string_and_fragment
    base_uri = 'http://www.example.org/style/basic.css'
    css = 'body { background: url(../style/yellow-dot_symbol$.png?abc=123&def=456#1011) };'

    sheet = Cataract::Stylesheet.new(absolute_paths: true, base_uri: base_uri)
    sheet.add_block(css)

    rule = sheet.rules.first

    assert_has_property(
      { background: "url('http://www.example.org/style/yellow-dot_symbol$.png?abc=123&def=456#1011')" },
      rule
    )
  end

  def test_convert_uris_in_list_style_image
    base_uri = 'http://www.example.org/directory/file.html'
    css = '.specs {font-family:Helvetica;font-weight:bold;list-style-image:url("images/bullet.gif");}'

    sheet = Cataract::Stylesheet.new(absolute_paths: true, base_uri: base_uri)
    sheet.add_block(css)

    rule = sheet.rules.first

    assert_has_property(
      { 'list-style-image': "url('http://www.example.org/directory/images/bullet.gif')" },
      rule
    )
  end

  def test_convert_uris_disabled_by_default
    base_uri = 'http://www.example.org/style/basic.css'
    css = "body { background: url('../style/yellow.png') };"

    # Without absolute_paths: true, URLs should remain relative
    sheet = Cataract::Stylesheet.new(base_uri: base_uri)
    sheet.add_block(css)

    rule = sheet.rules.first

    assert_has_property({ background: "url('../style/yellow.png')" }, rule)
  end

  def test_convert_uris_requires_base_uri
    css = "body { background: url('../style/yellow.png') };"

    # With absolute_paths but no base_uri, URLs should remain unchanged
    sheet = Cataract::Stylesheet.new(absolute_paths: true)
    sheet.add_block(css)

    rule = sheet.rules.first

    assert_has_property({ background: "url('../style/yellow.png')" }, rule)
  end

  def test_convert_uris_preserves_absolute_urls
    base_uri = 'http://www.example.org/style/basic.css'
    css = "body { background: url('https://cdn.example.com/image.png') };"

    sheet = Cataract::Stylesheet.new(absolute_paths: true, base_uri: base_uri)
    sheet.add_block(css)

    rule = sheet.rules.first
    # Absolute URLs should remain unchanged
    assert_has_property({ background: "url('https://cdn.example.com/image.png')" }, rule)
  end

  def test_convert_uris_with_data_uri
    base_uri = 'http://www.example.org/style/basic.css'
    data_uri = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAUA'
    css = "body { background: url('#{data_uri}') };"

    sheet = Cataract::Stylesheet.new(absolute_paths: true, base_uri: base_uri)
    sheet.add_block(css)

    rule = sheet.rules.first
    # Data URIs should remain unchanged
    assert_has_property({ background: "url('#{data_uri}')" }, rule)
  end

  # ============================================================================
  # Per-block base_uri override
  # ============================================================================

  def test_add_block_base_uri_override
    sheet = Cataract::Stylesheet.new(
      absolute_paths: true,
      base_uri: 'http://default.example.org/css/'
    )

    # First block uses default
    sheet.add_block("body { background: url('bg.png') };")

    # Second block overrides
    sheet.add_block(
      ".header { background: url('header.png') };",
      base_uri: 'http://other.example.org/styles/'
    )

    # Third block back to default
    sheet.add_block(".footer { background: url('footer.png') };")

    rules = sheet.rules

    assert_has_property({ background: "url('http://default.example.org/css/bg.png')" }, rules[0])
    assert_has_property({ background: "url('http://other.example.org/styles/header.png')" }, rules[1])
    assert_has_property({ background: "url('http://default.example.org/css/footer.png')" }, rules[2])
  end

  def test_add_block_absolute_paths_override
    sheet = Cataract::Stylesheet.new(
      absolute_paths: true,
      base_uri: 'http://example.org/css/'
    )

    # First block uses constructor setting (convert)
    sheet.add_block("body { background: url('bg.png') };")

    # Second block disables conversion
    sheet.add_block(
      ".header { background: url('header.png') };",
      absolute_paths: false
    )

    rules = sheet.rules

    assert_has_property({ background: "url('http://example.org/css/bg.png')" }, rules[0])
    assert_has_property({ background: "url('header.png')" }, rules[1])
  end

  # ============================================================================
  # Import resolution with base_uri
  # ============================================================================

  def test_import_resolution_with_base_uri
    stub_request(:get, 'https://example.com/css/imported.css')
      .to_return(status: 200, body: '.imported { color: blue; }')

    css = '@import "imported.css"; body { color: red; }'

    sheet = Cataract::Stylesheet.new(
      import: true,
      base_uri: 'https://example.com/css/main.css'
    )
    sheet.add_block(css)

    assert_equal 2, sheet.size
    assert_has_selector '.imported', sheet
    assert_has_selector 'body', sheet
  end

  def test_import_resolution_with_base_uri_override
    stub_request(:get, 'https://cdn-a.example.com/styles/reset.css')
      .to_return(status: 200, body: '.reset-a { margin: 0; }')

    stub_request(:get, 'https://cdn-b.example.com/css/reset.css')
      .to_return(status: 200, body: '.reset-b { padding: 0; }')

    sheet = Cataract::Stylesheet.new(
      import: true,
      base_uri: 'https://cdn-a.example.com/styles/main.css'
    )

    # First block uses default base_uri
    sheet.add_block('@import "reset.css";')

    # Second block overrides base_uri
    sheet.add_block(
      '@import "reset.css";',
      base_uri: 'https://cdn-b.example.com/css/app.css'
    )

    assert_equal 2, sheet.size
    assert_has_selector '.reset-a', sheet
    assert_has_selector '.reset-b', sheet
  end

  def test_import_resolution_with_relative_path
    stub_request(:get, 'https://example.com/shared/reset.css')
      .to_return(status: 200, body: '.reset { margin: 0; }')

    css = '@import "../shared/reset.css";'

    sheet = Cataract::Stylesheet.new(
      import: true,
      base_uri: 'https://example.com/css/main.css'
    )
    sheet.add_block(css)

    assert_equal 1, sheet.size
    assert_has_selector '.reset', sheet
  end

  # ============================================================================
  # Import resolution with base_dir (local files)
  # ============================================================================

  def test_import_resolution_with_base_dir
    Dir.mktmpdir do |dir|
      # Create imported file
      imported_file = File.join(dir, 'imported.css')
      File.write(imported_file, '.imported { color: blue; }')

      css = '@import "imported.css"; body { color: red; }'

      sheet = Cataract::Stylesheet.new(
        import: { allowed_schemes: ['file'] },
        base_dir: dir
      )
      sheet.add_block(css)

      assert_equal 2, sheet.size
      assert_has_selector '.imported', sheet
      assert_has_selector 'body', sheet
    end
  end

  def test_import_resolution_with_base_dir_override
    Dir.mktmpdir do |dir|
      # Create two subdirectories with different CSS files
      dir_a = File.join(dir, 'a')
      dir_b = File.join(dir, 'b')
      Dir.mkdir(dir_a)
      Dir.mkdir(dir_b)

      File.write(File.join(dir_a, 'style.css'), '.from-a { color: red; }')
      File.write(File.join(dir_b, 'style.css'), '.from-b { color: blue; }')

      sheet = Cataract::Stylesheet.new(
        import: { allowed_schemes: ['file'] },
        base_dir: dir_a
      )

      # First block uses default base_dir
      sheet.add_block('@import "style.css";')

      # Second block overrides base_dir
      sheet.add_block(
        '@import "style.css";',
        base_dir: dir_b
      )

      assert_equal 2, sheet.size
      assert_has_selector '.from-a', sheet
      assert_has_selector '.from-b', sheet
    end
  end

  def test_import_resolution_with_relative_path_in_base_dir
    Dir.mktmpdir do |dir|
      # Create nested directory structure
      css_dir = File.join(dir, 'css')
      shared_dir = File.join(dir, 'shared')
      Dir.mkdir(css_dir)
      Dir.mkdir(shared_dir)

      File.write(File.join(shared_dir, 'reset.css'), '.reset { margin: 0; }')

      css = '@import "../shared/reset.css";'

      sheet = Cataract::Stylesheet.new(
        import: { allowed_schemes: ['file'] },
        base_dir: css_dir
      )
      sheet.add_block(css)

      assert_equal 1, sheet.size
      assert_has_selector '.reset', sheet
    end
  end

  # ============================================================================
  # Combined URL conversion and import resolution
  # ============================================================================

  def test_url_conversion_in_imported_files
    stub_request(:get, 'https://example.com/css/imported.css')
      .to_return(status: 200, body: ".imported { background: url('images/bg.png'); }")

    css = '@import "imported.css";'

    sheet = Cataract::Stylesheet.new(
      import: true,
      absolute_paths: true,
      base_uri: 'https://example.com/css/main.css'
    )
    sheet.add_block(css)

    rule = sheet.rules.first
    # URL in imported file should also be converted
    assert_has_property({ background: "url('https://example.com/css/images/bg.png')" }, rule)
  end

  def test_nested_imports_with_url_conversion
    stub_request(:get, 'https://example.com/css/level1.css')
      .to_return(status: 200, body: "@import 'sub/level2.css'; .level1 { background: url('l1.png'); }")

    stub_request(:get, 'https://example.com/css/sub/level2.css')
      .to_return(status: 200, body: ".level2 { background: url('l2.png'); }")

    css = '@import "level1.css";'

    sheet = Cataract::Stylesheet.new(
      import: true,
      absolute_paths: true,
      base_uri: 'https://example.com/css/main.css'
    )
    sheet.add_block(css)

    level1_rule = sheet.rules.find { |r| r.selector == '.level1' }
    level2_rule = sheet.rules.find { |r| r.selector == '.level2' }

    assert_has_property({ background: "url('https://example.com/css/l1.png')" }, level1_rule)
    assert_has_property({ background: "url('https://example.com/css/sub/l2.png')" }, level2_rule)
  end

  # ============================================================================
  # Edge cases
  # ============================================================================

  def test_multiple_url_declarations_in_same_rule
    base_uri = 'http://example.org/css/main.css'
    css = <<~CSS
      .multiple {
        background-image: url('bg.png');
        list-style-image: url('../images/bullet.gif');
        cursor: url('cursors/pointer.cur'), auto;
      }
    CSS

    sheet = Cataract::Stylesheet.new(absolute_paths: true, base_uri: base_uri)
    sheet.add_block(css)

    rule = sheet.rules.first

    assert_has_property({ 'background-image': "url('http://example.org/css/bg.png')" }, rule)
    assert_has_property({ 'list-style-image': "url('http://example.org/images/bullet.gif')" }, rule)
    assert_has_property({ cursor: "url('http://example.org/css/cursors/pointer.cur'), auto" }, rule)
  end

  def test_url_in_font_face
    base_uri = 'http://example.org/css/main.css'
    css = "@font-face { font-family: 'MyFont'; src: url('fonts/myfont.woff2') format('woff2'), url('../fonts/myfont.woff') format('woff'); }"

    sheet = Cataract::Stylesheet.new(absolute_paths: true, base_uri: base_uri)
    sheet.add_block(css)

    # Assuming @font-face is parsed as an AtRule
    font_rule = sheet.rules.first

    assert_has_property(
      { src: "url('http://example.org/css/fonts/myfont.woff2') format('woff2'), url('http://example.org/fonts/myfont.woff') format('woff')" },
      font_rule
    )
  end

  def test_empty_url
    base_uri = 'http://example.org/css/main.css'
    css = "body { background: url('') };"

    sheet = Cataract::Stylesheet.new(absolute_paths: true, base_uri: base_uri)
    sheet.add_block(css)

    rule = sheet.rules.first
    # Empty URL should remain empty or be handled gracefully
    assert_has_property({ background: "url('')" }, rule)
  end

  def test_chainable_add_block_with_different_options
    stub_request(:get, 'https://cdn-a.example.com/reset.css')
      .to_return(status: 200, body: '.reset { margin: 0; }')

    stub_request(:get, 'https://cdn-b.example.com/theme.css')
      .to_return(status: 200, body: '.theme { color: blue; }')

    sheet = Cataract::Stylesheet.new(import: true)
                                .add_block('@import "reset.css";', base_uri: 'https://cdn-a.example.com/')
                                .add_block('@import "theme.css";', base_uri: 'https://cdn-b.example.com/')
                                .add_block('body { color: black; }')

    assert_equal 3, sheet.size
    assert_has_selector '.reset', sheet
    assert_has_selector '.theme', sheet
    assert_has_selector 'body', sheet
  end

  def test_base_uri_with_port_number
    base_uri = 'http://localhost:3000/assets/css/main.css'
    css = "body { background: url('../images/bg.png') };"

    sheet = Cataract::Stylesheet.new(absolute_paths: true, base_uri: base_uri)
    sheet.add_block(css)

    rule = sheet.rules.first

    assert_has_property({ background: "url('http://localhost:3000/assets/images/bg.png')" }, rule)
  end

  def test_base_uri_with_username_password
    base_uri = 'http://user:pass@example.com/css/main.css'
    css = "body { background: url('bg.png') };"

    # Custom resolver that strips userinfo for security
    resolver = lambda { |base, relative|
      require 'uri'
      resolved = URI.parse(base).merge(relative)
      if resolved.userinfo
        resolved.user = nil
        resolved.password = nil
      end
      resolved.to_s
    }

    sheet = Cataract::Stylesheet.new(
      absolute_paths: true,
      base_uri: base_uri,
      uri_resolver: resolver
    )
    sheet.add_block(css)

    rule = sheet.rules.first
    # Auth info should be stripped by our custom resolver
    assert_has_property({ background: "url('http://example.com/css/bg.png')" }, rule)
  end

  # ============================================================================
  # Custom URI resolver
  # ============================================================================

  def test_custom_uri_resolver_with_addressable
    require 'addressable/uri'

    base_uri = 'http://example.com/css/main.css'
    css = "body { background: url('../images/bg.png') };"

    # Custom resolver using Addressable
    resolver = lambda { |base, relative|
      Addressable::URI.parse(base).join(relative).to_s
    }

    sheet = Cataract::Stylesheet.new(
      absolute_paths: true,
      base_uri: base_uri,
      uri_resolver: resolver
    )
    sheet.add_block(css)

    rule = sheet.rules.first

    assert_has_property({ background: "url('http://example.com/images/bg.png')" }, rule)
  end

  def test_custom_uri_resolver_error_handling
    base_uri = 'http://example.com/css/main.css'
    css = "body { background: url('invalid://[malformed') };"

    # Resolver that raises on invalid URIs
    resolver = lambda { |_base, _relative|
      raise URI::InvalidURIError, 'Invalid URI'
    }

    sheet = Cataract::Stylesheet.new(
      absolute_paths: true,
      base_uri: base_uri,
      uri_resolver: resolver
    )
    sheet.add_block(css)

    rule = sheet.rules.first
    # Should preserve original URL when resolver fails
    assert_has_property({ background: "url('invalid://[malformed')" }, rule)
  end
end
