# frozen_string_literal: true

require_relative 'test_helper'

class TestImplementation < Minitest::Test
  def test_implementation_matches_env_var
    if %w[1 true].include?(ENV['CATARACT_PURE'])
      assert_equal :ruby, Cataract::IMPLEMENTATION,
                   'ENV["CATARACT_PURE"] is set but native implementation is loaded - something is broken in require setup'
    else
      assert_equal :native, Cataract::IMPLEMENTATION,
                   'ENV["CATARACT_PURE"] is not set but pure Ruby implementation is loaded'
    end
  end

  if Cataract::IMPLEMENTATION == :native
    def test_native_implementation_basic_parse
      sheet = Cataract::Stylesheet.parse('body { color: red; }')

      assert_equal 1, sheet.rules.size
      assert_equal 'body', sheet.rules.first.selector
    end

    def test_native_extension_loaded_flag
      assert defined?(Cataract::NATIVE_EXTENSION_LOADED),
             'Native implementation should define NATIVE_EXTENSION_LOADED constant'
    end
  end

  if Cataract::IMPLEMENTATION == :ruby
    def test_ruby_implementation_basic_parse
      sheet = Cataract::Stylesheet.parse('body { color: red; }')

      assert_equal 1, sheet.rules.size
      assert_equal 'body', sheet.rules.first.selector
    end

    def test_pure_ruby_loaded_flag
      assert defined?(Cataract::PURE_RUBY_LOADED),
             'Pure Ruby implementation should define PURE_RUBY_LOADED constant'
    end
  end

  # convert_colors! only exists for real on native, and only once the
  # optional cataract/color_conversion extension is loaded (see
  # test_helper.rb) - it overrides Stylesheet's own NotImplementedError
  # stub. Pure Ruby never had a real implementation, so the stub stands.
  # Real conversion behavior itself is covered thoroughly in test/color/*.
  if Cataract::IMPLEMENTATION == :ruby
    def test_convert_colors_raises_not_implemented
      sheet = Cataract::Stylesheet.parse('body { color: red; }')
      error = assert_raises(NotImplementedError) do
        sheet.convert_colors!
      end
      assert_equal 'convert_colors! is not yet implemented in Cataract', error.message
    end
  else
    def test_convert_colors_is_implemented
      sheet = Cataract::Stylesheet.parse('body { color: #ff0000; }')
      sheet.convert_colors!(to: :rgb)

      assert_has_property({ color: 'rgb(255 0 0)' }, sheet.rules.first)
    end
  end
end
