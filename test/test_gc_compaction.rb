# frozen_string_literal: true

require 'test_helper'

# GC compaction moves objects. The native extension caches Cataract's struct
# and exception classes in C globals, and those pointers dangle after a move
# unless they are registered with the GC.
#
# Callers reach this without doing anything unusual: Process.warmup compacts,
# and it is standard practice to call it after boot. Every parse afterwards
# used to fail with "uninitialized class".
class TestGcCompaction < Minitest::Test
  CSS = <<~CSS
    @import url("other.css");
    body { color: red; margin: 10px 20px; }
    @media print { .a, .b { font: bold 12px/1.5 serif; } }
    @supports (display: grid) { .grid { display: grid; } }
  CSS

  # Moves every object it can, which is what makes this deterministic rather
  # than dependent on heap layout.
  def force_compaction
    GC.verify_compaction_references(expand_heap: true, toward: :empty)
  end

  def test_parses_after_compaction
    Cataract::Stylesheet.new.add_block(CSS) # populate the cached classes
    force_compaction

    sheet = Cataract::Stylesheet.new
    sheet.add_block(CSS)

    assert_equal 4, sheet.rules_count
  end

  def test_serializes_after_compaction
    sheet = Cataract::Stylesheet.new
    sheet.add_block(CSS)
    force_compaction

    reparsed = Cataract::Stylesheet.new
    reparsed.add_block(sheet.to_s)

    assert_has_selector 'body', reparsed
    assert_has_property({ color: 'red' }, reparsed.with_selector('body').first)
  end

  def test_flattens_after_compaction
    Cataract.flatten(Cataract.parse_css(CSS))
    force_compaction

    flattened = Cataract.flatten(Cataract.parse_css(CSS))

    refute_empty flattened.rules
  end

  def test_parses_after_process_warmup
    # The path that actually surfaced this: Process.warmup compacts the heap.
    Cataract::Stylesheet.new.add_block(CSS)
    Process.warmup

    sheet = Cataract::Stylesheet.new
    sheet.add_block(CSS)

    assert_equal 4, sheet.rules_count
  end

  def test_raises_parse_errors_after_compaction
    # Exception classes are cached in C globals too, so raising has to survive
    # a move as well.
    force_compaction

    assert_raises(Cataract::ParseError) do
      Cataract::Stylesheet.new(parser: { raise_parse_errors: true }).add_block('a { color: }')
    end
  end
end
