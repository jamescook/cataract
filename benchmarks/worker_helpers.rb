# frozen_string_literal: true

# Shared helper module for benchmark workers
#
# Provides common helpers for workers including:
# - JIT-aware impl_type determination (interpreter/YJIT/ZJIT)
# - A pre-flight check that the JIT actually active matches what the parent
#   process asked for, so a subprocess that silently failed to honor
#   --yjit/--zjit doesn't get measured and mislabeled as something else
# - Unique benchmark filenames to avoid overwriting results
module WorkerHelpers
  # Override benchmark_name to include impl_type suffix
  # This prevents different JIT variants from overwriting each other's results
  def benchmark_name
    "#{self.class.benchmark_name}_#{impl_type}"
  end

  private

  # Determines implementation type with a JIT suffix, verifying first that
  # the JIT actually active in this process is the one that was asked for.
  #
  # @param base_impl [Symbol] Base implementation (:pure, :native)
  # @param test_module [Module] Test module that provides yjit_applicable? method
  # @return [Symbol] Implementation type with JIT suffix if applicable
  #
  # Examples:
  #   determine_impl_type(:pure, ParsingTests)
  #   # => :pure_with_yjit (if YJIT enabled)
  #   # => :pure_with_zjit (if ZJIT enabled)
  #   # => :pure_without_yjit (if no JIT enabled)
  #
  #   determine_impl_type(:native, ParsingTests)
  #   # => :native (JIT variants not applicable to C extensions)
  def determine_impl_type(base_impl, test_module)
    return base_impl unless test_module.yjit_applicable?(base_impl)

    actual_jit = current_jit_mode
    verify_jit_mode!(actual_jit)

    case actual_jit
    when :zjit then :"#{base_impl}_with_zjit"
    when :yjit then :"#{base_impl}_with_yjit"
    else :"#{base_impl}_without_yjit"
    end
  end

  # Which JIT (if any) is actually active in this process right now. YJIT
  # and ZJIT are mutually exclusive in a single Ruby process, so at most one
  # of these is true.
  def current_jit_mode
    if defined?(RubyVM::ZJIT) && RubyVM::ZJIT.enabled?
      :zjit
    elsif defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?
      :yjit
    else
      :none
    end
  end

  # Confirms the JIT actually active matches CATARACT_BENCH_JIT, the mode the
  # parent process's subprocess launch (--disable-yjit/--yjit/--zjit)
  # intended. Without this, a Ruby built without YJIT/ZJIT support (or an
  # inherited RUBY_YJIT_ENABLE/RUBY_ZJIT_ENABLE env var overriding the flag)
  # would just warn and silently fall back to the interpreter - the run
  # would "succeed" but measure the wrong thing under the wrong label. Only
  # checks when CATARACT_BENCH_JIT is set, so running a worker standalone
  # for debugging (no env var) is unaffected.
  def verify_jit_mode!(actual_jit)
    expected_jit = ENV.fetch('CATARACT_BENCH_JIT', nil)
    return unless expected_jit
    return if expected_jit == actual_jit.to_s

    raise "JIT mode mismatch: expected CATARACT_BENCH_JIT=#{expected_jit} but RubyVM reports " \
          "#{actual_jit} is active (#{RUBY_DESCRIPTION}) - was this Ruby built with YJIT/ZJIT support?"
  end
end
