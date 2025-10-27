#!/usr/bin/env ruby
# Simple CSS parser fuzzer
# Usage: ruby test/fuzz_css_parser.rb [iterations] [rng_seed]
#   iterations: number of fuzzing iterations (default: 10,000)
#   rng_seed:   random number generator seed for reproducibility (default: random)

require 'timeout'
require 'open3'
require 'rbconfig'
require_relative '../lib/cataract'

# Check if Ruby is compiled with AddressSanitizer (ASAN)
# ASAN provides detailed heap-buffer-overflow and use-after-free reports
def check_asan_enabled
  ruby_bin = RbConfig.ruby

  # Check for ASAN library linkage (cross-platform)
  case RbConfig::CONFIG['host_os']
  when /darwin|mac os/
    # macOS: use otool to check dynamic libraries
    output = `otool -L "#{ruby_bin}" 2>&1`
    output.include?('asan')
  when /linux/
    # Linux: use ldd to check dynamic libraries
    output = `ldd "#{ruby_bin}" 2>&1`
    output.include?('asan')
  else
    # Unknown platform - assume not enabled
    false
  end
rescue => e
  # If check fails, assume not enabled
  false
end

unless check_asan_enabled
  $stderr.puts "=" * 80
  $stderr.puts "WARNING: Ruby not compiled with AddressSanitizer (ASAN)"
  $stderr.puts "=" * 80
  $stderr.puts "Crash reports will have limited utility for debugging memory errors."
  $stderr.puts ""
  $stderr.puts "To enable ASAN, recompile Ruby with these flags:"
  $stderr.puts "  CFLAGS=\"-fsanitize=address -g -O1\" LDFLAGS=\"-fsanitize=address\""
  $stderr.puts ""
  $stderr.puts "Example with mise:"
  $stderr.puts "  CFLAGS=\"-fsanitize=address -g -O1\" LDFLAGS=\"-fsanitize=address\" mise install ruby@#{RUBY_VERSION} --force"
  $stderr.puts ""
  $stderr.puts "Example with rbenv/ruby-build:"
  $stderr.puts "  CFLAGS=\"-fsanitize=address -g -O1\" LDFLAGS=\"-fsanitize=address\" rbenv install #{RUBY_VERSION}"
  $stderr.puts ""
  $stderr.puts "ASAN provides detailed reports for:"
  $stderr.puts "  - Heap buffer overflows"
  $stderr.puts "  - Use-after-free bugs"
  $stderr.puts "  - Stack buffer overflows"
  $stderr.puts "  - Memory leaks"
  $stderr.puts "=" * 80
  $stderr.puts ""
end

ITERATIONS = (ARGV[0] || 10_000).to_i
RNG_SEED = (ARGV[1] || Random.new_seed).to_i

# Set the random seed for reproducibility
srand(RNG_SEED)

# Load bootstrap.css as main seed
BOOTSTRAP_CSS = File.read(File.join(__dir__, 'fixtures/bootstrap.css'))

# CSS corpus - real CSS snippets to mutate
CORPUS = [
  BOOTSTRAP_CSS,  # Full bootstrap.css
  # Interesting subsections of bootstrap
  BOOTSTRAP_CSS[0..5000],
  BOOTSTRAP_CSS[10000..20000],
  BOOTSTRAP_CSS[-5000..-1],
  # Small focused examples
  "body { margin: 0; }",
  "div.class { color: red; background: url('data:image/png;base64,ABC'); }",
  "#id > p:hover::before { content: 'test'; }",
  "a[href^='https'] { color: blue !important; }",
  "@keyframes fade { from { opacity: 0; } to { opacity: 1; } }",
  "@font-face { font-family: 'Custom'; src: url('font.woff'); }",
  "h1 + *[rel=up] { margin: 10px 20px; }",
  "li.red.level { border: 1px solid red; }",
  "/* comment */ .test { padding: 0; }",

  # Media query parsing - test parse_media_query() function
  "@media screen { .nav { display: flex; } }",
  "@media print { body { margin: 1in; } }",
  "@media screen, print { .dual { color: black; } }",
  "@media screen and (min-width: 768px) { .responsive { width: 100%; } }",
  "@media (prefers-color-scheme: dark) { body { background: black; } }",
  "@media only screen and (max-width: 600px) { .mobile { font-size: 12px; } }",
  "@media not print { .no-print { display: none; } }",
  "@media screen and (min-width: 768px) and (max-width: 1024px) { .tablet { padding: 20px; } }",
  "@media (orientation: landscape) { .landscape { width: 100vw; } }",
  "@media screen and (color) { .color { background: red; } }",
  "@media (min-resolution: 2dppx) { .retina { background-image: url('hi-res.png'); } }",
  "@media (-webkit-min-device-pixel-ratio: 2) { .webkit { content: 'vendor'; } }",

  # Deep nesting - close to MAX_PARSE_DEPTH (10)
  # Depth 8 - mutations can push it over the limit
  "@supports (a) { @media (b) { @supports (c) { @layer d { @container (e) { @scope (f) { @media (g) { @supports (h) { body { margin: 0; } } } } } } } }",

  # Long property names - close to MAX_PROPERTY_NAME_LENGTH (256)
  "body { #{'a' * 200}-property: value; }",

  # Long property values - close to MAX_PROPERTY_VALUE_LENGTH (32KB)
  "body { background: url('data:image/svg+xml,#{'A' * 30000}'); }",
  "div { content: '#{'x' * 31000}'; }",

  # Multiple nested @supports to stress recursion
  "@supports (display: flex) { @supports (gap: 1rem) { div { display: flex; } } }"
]

# Mutation strategies (binary-safe)
def mutate(css)
  # Work with dup to avoid mutating original
  css = css.dup.force_encoding('UTF-8')

  mutations = [
    # Basic mutations
    -> { css[0..rand(css.length)] },  # Truncate
    -> { pos = rand(css.length); css.insert(pos, css[0..rand(css.length)]) },  # Duplicate section
    -> { css.bytes.select { rand > 0.1 }.pack('C*').force_encoding('UTF-8') },  # Delete random bytes
    -> { bytes = css.bytes; 10.times { a, b = rand(bytes.size), rand(bytes.size); bytes[a], bytes[b] = bytes[b], bytes[a] }; bytes.pack('C*').force_encoding('UTF-8') },  # Swap bytes

    # Brace/bracket corruption
    -> { css.gsub(/{/, '').gsub(/}/, '') },  # Remove braces
    -> { css.gsub(/{/, '{{').gsub(/}/, '}}') },  # Duplicate braces
    -> { css + '{' * rand(5) },  # Unmatched braces
    -> { css.gsub(/\{/, '[').gsub(/\}/, ']') },  # Wrong bracket type

    # Quote corruption
    -> { css.gsub(/["']/, '') },  # Remove quotes
    -> { css.gsub(/"/, "'").gsub(/'/, '"') },  # Swap quote types
    -> { css.gsub(/(['"])/, '\1\1') },  # Double quotes

    # @rule mutations
    -> { "@media print { #{css} @media screen { #{css} } }" },  # Deep nesting
    -> { css.gsub(/@media/, '@MEDIA').gsub(/@keyframes/, '@KEYFRAMES') },  # Wrong case
    -> { css.gsub(/@(media|keyframes|font-face)/) { "@#{rand(99999)}" } },  # Invalid @rules
    -> { "@supports (garbage) { #{css} }" },  # Invalid @supports

    # Selector mutations
    -> { css.gsub(/\.[\w-]+/, '..' + 'x' * rand(100)) },  # Corrupt class names
    -> { css.gsub(/#[\w-]+/, '##' + 'x' * rand(100)) },  # Corrupt IDs
    -> { css.gsub(/::?[\w-]+/, ':::' + 'x' * rand(50)) },  # Corrupt pseudo-elements
    -> { css.gsub(/\[[\w\-]+/, '[' + 'X' * rand(10)) },  # Corrupt attributes

    # Value mutations
    -> { css.gsub(/;/, ' !important;') },  # Add !important everywhere
    -> { css.gsub(/:[^;]+;/, ": #{'x' * rand(10000)};") },  # Very long values
    -> { css.gsub(/calc\([^)]+\)/, 'calc(' + '(' * rand(10) + '1+2' + ')' * rand(10)) },  # Unbalanced calc()
    -> { css.gsub(/url\([^)]+\)/, 'url(CORRUPT' + 'X' * rand(100) + ')') },  # Corrupt URLs
    -> { css.gsub(/rgba?\([^)]+\)/, 'rgb(' + [rand(999), rand(999), rand(999)].join(',') + ')') },  # Invalid rgb values

    # Binary corruption
    -> { pos = rand(css.length); css.insert(pos, [0, 255, 222, 173, 190, 239].pack('C*').force_encoding('UTF-8')) },  # Binary injection
    -> { css.bytes.map { |b| rand < 0.05 ? rand(256) : b }.pack('C*').force_encoding('UTF-8') },  # Bit flips

    # Comment corruption
    -> { css.gsub(/\/\*/, '/*' * rand(5)) },  # Nested comment starts
    -> { '/*' + css },  # Unclosed comment
    -> { css.gsub(/\*\//, '') }  # Remove comment ends
  ]

  result = mutations.sample.call
  result.force_encoding('UTF-8') rescue result.force_encoding('ASCII-8BIT')
  result
end

# Stats tracking
stats = {
  total: 0,
  parsed: 0,
  merge_tested: 0,
  to_s_tested: 0,
  parse_errors: 0,
  depth_errors: 0,
  size_errors: 0,
  crashes: 0
}

# Configure timeout based on GC.stress mode
WORKER_TIMEOUT = ENV['FUZZ_GC_STRESS'] == '1' ? 300 : 10  # 5 minutes for GC.stress, 10 seconds normal

puts "Starting CSS parser fuzzer (#{ITERATIONS} iterations)..."
puts "RNG seed: #{RNG_SEED} (use this to reproduce crashes)"
puts "Corpus: #{CORPUS.length} CSS samples"
if ENV['FUZZ_GC_STRESS'] == '1'
  puts "GC.stress: ENABLED (expect 100-1000x slowdown, #{WORKER_TIMEOUT}s timeout)"
end
puts ""

# Worker script runs in subprocess and parses inputs from stdin
WORKER_SCRIPT = <<~'RUBY'
  require "cataract"

  # Configure aggressive GC to help identify memory leaks
  # Disable auto_compact - it can cause issues with C extensions holding pointers
  GC.auto_compact = false
  GC.config(
    malloc_limit: 1_000_000,
    malloc_limit_growth_factor: 1.1,   # Grow very slowly
    oldmalloc_limit_growth_factor: 1.1 # Grow very slowly
  )

  # Enable GC.stress mode if requested (VERY slow, but makes GC bugs reproducible)
  if ENV['FUZZ_GC_STRESS'] == '1'
    GC.stress = true
    STDERR.puts "[Worker] GC.stress enabled - expect 100-1000x slowdown"
  end

  # Read length-prefixed inputs and parse them
  loop do
    # Read 4-byte length prefix (network byte order)
    len_bytes = STDIN.read(4)
    break if len_bytes.nil? || len_bytes.bytesize != 4

    length = len_bytes.unpack1('N')

    # Read CSS input
    css = STDIN.read(length)
    break if css.nil? || css.bytesize != length

    # Parse CSS (crash will kill subprocess)
    begin
      rules = Cataract.parse_css(css)
      merge_tested = false
      to_s_tested = false

      # Test merge with valid CSS followed by fuzzed CSS
      # This tests merge error handling when second rule set is invalid
      begin
        valid_rules = Cataract.parse_css("body { margin: 0; color: red; }")
        combined_rules = valid_rules + rules
        Cataract.merge(combined_rules)
        merge_tested = true
      rescue Cataract::Error
        # Expected - merge might fail on invalid CSS
      end

      # Test to_s on parsed rules occasionally
      # This tests serialization on fuzzed data
      if !rules.empty? && rand < 0.01
        merged = Cataract.merge(rules)
        Cataract.declarations_to_s(merged)
        to_s_tested = true
      end

      # Report what was tested: PARSE [+MERGE] [+TOS]
      output = "PARSE"
      output += "+MERGE" if merge_tested
      output += "+TOS" if to_s_tested
      STDOUT.write("#{output}\n")
    rescue Cataract::DepthError
      STDOUT.write("DEPTH\n")
    rescue Cataract::SizeError
      STDOUT.write("SIZE\n")
    rescue Cataract::ParseError, Cataract::Error
      STDOUT.write("PARSEERR\n")
    rescue => e
      STDOUT.write("ERR\n")
    end
    STDOUT.flush
  end
RUBY

# Spawn a worker subprocess
def spawn_worker
  # Pass environment explicitly to ensure FUZZ_GC_STRESS is inherited
  env = ENV.to_h
  Open3.popen3(env, RbConfig.ruby, '-Ilib', '-e', WORKER_SCRIPT)
end

# Send input to worker and check result
# Returns: [:success | :error | :crash, error_message, crashed_input, stderr_output]
def parse_in_worker(stdin, stdout, stderr, wait_thr, input, last_input)
  # Check if worker is still alive BEFORE writing
  if !wait_thr.alive?
    status = wait_thr.value
    signal = status.termsig
    # Worker died on PREVIOUS input, not this one - collect stderr
    stderr_output = stderr.read_nonblock(100_000) rescue ""
    error_msg = signal ? "Signal #{signal} (#{Signal.signame(signal)})" : "Exit code #{status.exitstatus}"
    return [:crash, error_msg, last_input, stderr_output, false, false]
  end

  # Send length-prefixed input
  stdin.write([input.bytesize].pack('N'))
  stdin.write(input)
  stdin.flush

  # Wait for response with timeout
  ready = IO.select([stdout], nil, nil, WORKER_TIMEOUT)

  if ready.nil?
    # Timeout - worker hung, kill it
    Process.kill('KILL', wait_thr.pid) rescue nil
    stderr_output = stderr.read_nonblock(100_000) rescue ""
    [:crash, "Timeout (infinite loop?)", input, stderr_output, false, false]
  elsif !wait_thr.alive?
    # Worker crashed DURING this input
    status = wait_thr.value
    signal = status.termsig
    stderr_output = stderr.read_nonblock(100_000) rescue ""
    error_msg = signal ? "Signal #{signal} (#{Signal.signame(signal)})" : "Exit code #{status.exitstatus}"
    [:crash, error_msg, input, stderr_output, false, false]
  else
    # Read response
    response = stdout.gets&.strip
    case response
    when /^PARSE/
      # Extract which operations were tested
      merge_tested = response.include?("+MERGE")
      to_s_tested = response.include?("+TOS")
      [:success, nil, nil, nil, merge_tested, to_s_tested]
    when "DEPTH"
      [:depth_error, nil, nil, nil, false, false]
    when "SIZE"
      [:size_error, nil, nil, nil, false, false]
    when "PARSEERR"
      [:parse_error, nil, nil, nil, false, false]
    else
      [:error, nil, nil, nil, false, false]
    end
  end
rescue Errno::EPIPE, IOError
  # Pipe broken - worker already dead (check if it died on previous input)
  if !wait_thr.alive?
    status = wait_thr.value
    signal = status.termsig
    stderr_output = stderr.read_nonblock(100_000) rescue ""
    error_msg = signal ? "Signal #{signal} (#{Signal.signame(signal)})" : "Exit code #{status.exitstatus}"
    [:crash, error_msg, last_input, stderr_output, false, false]
  else
    [:crash, "Broken pipe", input, "", false, false]
  end
end

start_time = Time.now
crash_file = File.join(__dir__, 'fuzz_last_input.css')

# Spawn initial worker subprocess
stdin, stdout, stderr, wait_thr = spawn_worker
last_input = nil

ITERATIONS.times do |i|
  # Pick a seed and mutate it, or generate pure garbage occasionally
  input = if rand < 0.95
    mutate(CORPUS.sample)
  else
    # Pure garbage
    Array.new(rand(1000)) { rand(256).chr }.join
  end

  stats[:total] += 1

  # Send to worker subprocess
  result, error, crashed_input, stderr_output, merge_tested, to_s_tested = parse_in_worker(stdin, stdout, stderr, wait_thr, input, last_input)
  last_input = input

  case result
  when :success
    stats[:parsed] += 1
    stats[:merge_tested] += 1 if merge_tested
    stats[:to_s_tested] += 1 if to_s_tested
  when :parse_error
    stats[:parse_errors] += 1
  when :depth_error
    stats[:depth_errors] += 1
  when :size_error
    stats[:size_errors] += 1
  when :crash
    stats[:crashes] += 1

    # Use the actual crashed input (might be previous input if worker died between calls)
    actual_crash = crashed_input || input

    # Save crash files
    crash_save = File.join(__dir__, "fuzz_crash_#{Time.now.to_i}.css")
    crash_log = crash_save.sub(/\.css$/, '.log')

    File.binwrite(crash_save, actual_crash)
    File.binwrite(crash_file, actual_crash)  # Also save as last input for easy debugging

    # Determine if this is a real crash (SEGV) or just broken pipe (worker disappeared)
    is_real_crash = stderr_output && !stderr_output.empty?
    crash_type = is_real_crash ? "CRASH" : "WORKER DEATH"

    # Save stderr output (stack trace, etc.)
    if is_real_crash
      File.write(crash_log, stderr_output)
    end

    # Print crash to stderr so it doesn't get overwritten by progress line
    if is_real_crash
      $stderr.puts "\n!!! CRASH FOUND (SEGV) !!!"
      $stderr.puts "Saved crashing input to: #{crash_save}"
      $stderr.puts "Saved crash output to: #{crash_log}"
    else
      $stderr.puts "\n!!! WORKER DIED (#{error}) !!!"
      $stderr.puts "Saved input to: #{crash_save}"
      $stderr.puts "Note: No crash dump (worker may have been OOM-killed or died on previous input)"
    end
    $stderr.puts "Reproduce with: ruby -Ilib test/fuzz_css_parser.rb #{ITERATIONS} #{RNG_SEED}"
    $stderr.puts "Input size: #{actual_crash.length} bytes"
    $stderr.puts "Input preview: #{actual_crash.inspect[0..200]}"
    if is_real_crash
      $stderr.puts "Error: #{error}"
    end
    if crashed_input != input && crashed_input
      $stderr.puts "Note: Crash detected on PREVIOUS input (worker died before processing current input)"
    end
    $stderr.puts ""

    # Respawn worker to continue fuzzing
    stdin.close rescue nil
    stdout.close rescue nil
    stderr.close rescue nil
    stdin, stdout, stderr, wait_thr = spawn_worker
  end

  # Progress
  if (i + 1) % 1000 == 0
    elapsed = Time.now - start_time
    rate = (i + 1) / elapsed

    # Get worker memory usage (cross-platform)
    rss_mb = begin
      if File.exist?("/proc/#{wait_thr.pid}/status")
        # Linux: read from /proc filesystem
        status = File.read("/proc/#{wait_thr.pid}/status")
        if status =~ /VmRSS:\s+(\d+)\s+kB/
          $1.to_i / 1024.0
        else
          0.0
        end
      else
        # macOS/BSD: use ps command
        rss_kb = `ps -o rss= -p #{wait_thr.pid}`.strip.to_i
        rss_kb / 1024.0
      end
    rescue
      0.0
    end

    progress = "#{(i + 1).to_s.rjust(6)}/#{ITERATIONS}"
    iter_rate = "(#{rate.round(1).to_s.rjust(6)} iter/sec)"
    parsed = "Parsed: #{stats[:parsed].to_s.rjust(5)}"
    merged = "Merged: #{stats[:merge_tested].to_s.rjust(5)}"
    to_s = "ToS: #{stats[:to_s_tested].to_s.rjust(4)}"
    parse_err = "Err: #{stats[:parse_errors].to_s.rjust(4)}"
    crashes = "Crash: #{stats[:crashes].to_s.rjust(2)}"
    memory = "Mem: #{rss_mb.round(1).to_s.rjust(6)} MB"

    # Use \r to overwrite the same line
    print "\rProgress: #{progress} #{iter_rate} | #{parsed} | #{merged} | #{to_s} | #{parse_err} | #{crashes} | #{memory}"
    $stdout.flush
  end
end

# Print newline after final progress update
puts ""

# Clean up worker subprocess
stdin.close rescue nil
stdout.close rescue nil
stderr.close rescue nil
Process.kill('TERM', wait_thr.pid) rescue nil
wait_thr.join rescue nil

elapsed = Time.now - start_time

puts "\n" + "=" * 60
puts "Fuzzing complete!"
puts "Time: #{elapsed.round(2)}s (#{(stats[:total] / elapsed).round(1)} iter/sec)"
puts "Total: #{stats[:total]}"
puts "Parsed: #{stats[:parsed]} (#{(stats[:parsed] * 100.0 / stats[:total]).round(1)}%)"
puts "Merge tested: #{stats[:merge_tested]} (#{(stats[:merge_tested] * 100.0 / stats[:total]).round(1)}%)"
puts "ToS tested: #{stats[:to_s_tested]} (#{(stats[:to_s_tested] * 100.0 / stats[:total]).round(1)}%)"
puts "Parse Errors: #{stats[:parse_errors]} (#{(stats[:parse_errors] * 100.0 / stats[:total]).round(1)}%)"
puts "Depth Errors: #{stats[:depth_errors]} (#{(stats[:depth_errors] * 100.0 / stats[:total]).round(1)}%)"
puts "Size Errors: #{stats[:size_errors]} (#{(stats[:size_errors] * 100.0 / stats[:total]).round(1)}%)"
puts "Crashes: #{stats[:crashes]}"
puts "=" * 60

exit(stats[:crashes] > 0 ? 1 : 0)
