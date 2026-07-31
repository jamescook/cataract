# frozen_string_literal: true

# Stands in for RubyVM so JIT detection can be exercised for every mode,
# rather than only the one the test process happens to be running under.
#
# RubyMode only ever asks a VM three things - does the constant exist, hand
# it over, and is it enabled - so that is the whole surface.
class FakeVM
  # A stand-in for RubyVM::YJIT / RubyVM::ZJIT.
  class FakeJit
    def initialize(enabled:, stats: {})
      @enabled = enabled
      @stats = stats
    end

    attr_reader :stats

    def enabled?
      @enabled
    end

    # YJIT and ZJIT name this differently; RubyMode knows which to call.
    alias runtime_stats stats
  end

  # A VM with no JIT support compiled in at all.
  def self.without_jits
    new({})
  end

  # @param jits [Hash{Symbol => FakeJit}] constants this VM defines
  def initialize(jits)
    @jits = jits
  end

  # @param name [Symbol] e.g. :YJIT
  def self.with(name, enabled: true, stats: {})
    new(name => FakeJit.new(enabled: enabled, stats: stats))
  end

  def const_defined?(name)
    @jits.key?(name)
  end

  def const_get(name)
    @jits.fetch(name)
  end
end
