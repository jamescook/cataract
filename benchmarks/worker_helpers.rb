# frozen_string_literal: true

# Shared helper module for benchmark workers
#
# Provides common helpers for workers including:
# - YJIT-aware impl_type determination
# - Unique benchmark filenames to avoid overwriting results
module WorkerHelpers
  # Override benchmark_name to include impl_type suffix
  # This prevents different YJIT variants from overwriting each other's results
  def benchmark_name
    "#{self.class.benchmark_name}_#{impl_type}"
  end

  private

  # Determines implementation type with YJIT suffix based on actual YJIT status
  #
  # @param base_impl [Symbol] Base implementation (:pure, :native)
  # @param test_module [Module] Test module that provides yjit_applicable? method
  # @return [Symbol] Implementation type with YJIT suffix if applicable
  #
  # Examples:
  #   determine_impl_type_with_yjit(:pure, ParsingTests)
  #   # => :pure_with_yjit (if YJIT enabled)
  #   # => :pure_without_yjit (if YJIT disabled)
  #
  #   determine_impl_type_with_yjit(:native, ParsingTests)
  #   # => :native (YJIT not applicable to C extensions)
  def determine_impl_type_with_yjit(base_impl, test_module)
    return base_impl unless test_module.yjit_applicable?(base_impl)

    yjit_enabled = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled?
    yjit_enabled ? :"#{base_impl}_with_yjit" : :"#{base_impl}_without_yjit"
  end
end
