require "benchmark/ips"
require "cataract"

# Load css_parser for comparison
begin
  require "css_parser"
  CSS_PARSER_AVAILABLE = true
rescue LoadError
  CSS_PARSER_AVAILABLE = false
  puts "Warning: css_parser gem not found. Install with: gem install css_parser"
  puts "Running Cataract-only benchmarks..."
end

# Test values
MARGIN_VALUES = [
  "10px",
  "10px 20px",
  "10px 20px 30px",
  "10px 20px 30px 40px",
  "10px calc(100% - 20px)",
  "10px !important"
]

BORDER_VALUES = [
  "1px solid red",
  "2px dashed blue",
  "thin dotted #000"
]

FONT_VALUES = [
  "12px Arial",
  "bold 14px/1.5 'Helvetica Neue', sans-serif"
]

puts "\n=== Shorthand Expansion Benchmark ==="
puts "Comparing Cataract (C) vs css_parser (Ruby)\n\n"

# Sanity check: verify both implementations produce same results
if CSS_PARSER_AVAILABLE
  puts "--- Sanity Check: Comparing Outputs ---"

  # Test margin expansion
  cataract_result = Cataract.expand_margin("10px 20px 30px 40px")
  css_parser_rs = CssParser::RuleSet.new(block: "margin: 10px 20px 30px 40px")
  css_parser_rs.expand_shorthand!
  css_parser_result = {}
  css_parser_rs.each_declaration { |prop, val, _| css_parser_result[prop] = val }

  if cataract_result == css_parser_result
    puts "✓ Margin expansion: MATCH"
  else
    puts "✗ Margin expansion: MISMATCH"
    puts "  Cataract: #{cataract_result.inspect}"
    puts "  css_parser: #{css_parser_result.inspect}"
    exit 1
  end

  # Test border expansion
  cataract_result = Cataract.expand_border("1px solid red")
  css_parser_rs = CssParser::RuleSet.new(block: "border: 1px solid red")
  css_parser_rs.expand_shorthand!
  css_parser_result = {}
  css_parser_rs.each_declaration { |prop, val, _| css_parser_result[prop] = val }

  if cataract_result == css_parser_result
    puts "✓ Border expansion: MATCH"
  else
    puts "✗ Border expansion: MISMATCH"
    puts "  Cataract: #{cataract_result.inspect}"
    puts "  css_parser: #{css_parser_result.inspect}"
    exit 1
  end

  puts "All sanity checks passed!\n\n"
end

# Margin expansion
puts "--- Margin Expansion (4 values) ---"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Cataract (C)") do
    Cataract.expand_margin("10px 20px 30px 40px")
  end

  if CSS_PARSER_AVAILABLE
    x.report("css_parser (Ruby)") do
      rs = CssParser::RuleSet.new(block: "margin: 10px 20px 30px 40px")
      rs.expand_shorthand!
    end
  end

  x.compare!
end

# Margin with calc()
puts "\n--- Margin with calc() ---"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Cataract (C)") do
    Cataract.expand_margin("10px calc(100% - 20px)")
  end

  if CSS_PARSER_AVAILABLE
    x.report("css_parser (Ruby)") do
      rs = CssParser::RuleSet.new(block: "margin: 10px calc(100% - 20px)")
      rs.expand_shorthand!
    end
  end

  x.compare!
end

# Margin with !important
puts "\n--- Margin with !important ---"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Cataract (C)") do
    Cataract.expand_margin("10px !important")
  end

  if CSS_PARSER_AVAILABLE
    x.report("css_parser (Ruby)") do
      rs = CssParser::RuleSet.new(block: "margin: 10px !important")
      rs.expand_shorthand!
    end
  end

  x.compare!
end

# Border expansion
puts "\n--- Border Expansion ---"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Cataract (C)") do
    Cataract.expand_border("1px solid red")
  end

  if CSS_PARSER_AVAILABLE
    x.report("css_parser (Ruby)") do
      rs = CssParser::RuleSet.new(block: "border: 1px solid red")
      rs.expand_shorthand!
    end
  end

  x.compare!
end

# Font expansion
puts "\n--- Font Expansion ---"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("Cataract (C)") do
    Cataract.expand_font("bold 14px/1.5 'Helvetica Neue', sans-serif")
  end

  if CSS_PARSER_AVAILABLE
    x.report("css_parser (Ruby)") do
      rs = CssParser::RuleSet.new(block: "font: bold 14px/1.5 'Helvetica Neue', sans-serif")
      rs.expand_shorthand!
    end
  end

  x.compare!
end

puts "\n=== Summary ==="
puts "Cataract uses a C implementation with Ragel state machine for value splitting"
puts "css_parser uses pure Ruby with regex-based parsing"
