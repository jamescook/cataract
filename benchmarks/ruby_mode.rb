# frozen_string_literal: true

# One Ruby VM configuration a benchmark can run under: no JIT, YJIT, or ZJIT.
#
# Owns everything that varies by mode - the flags that launch it, how to
# detect it in a running VM, its labels, and how to read its JIT statistics.
# Adding a mode means adding one constant here.
#
# The VM and the environment are passed in rather than read globally, so
# detection and verification are testable without a matching subprocess.
class RubyMode
  # Set by a parent process to declare which mode a worker should be in.
  ENV_VAR = 'CATARACT_BENCH_JIT'

  Mismatch = Class.new(StandardError)

  attr_reader :id, :cli_flags, :label, :column_label, :vm_constant

  def initialize(id:, cli_flags:, label:, column_label:, detector:, vm_constant: nil,
                 stats_reader: ->(_vm) { {} })
    @id = id
    @cli_flags = cli_flags.freeze
    @label = label
    @column_label = column_label
    @detector = detector
    @vm_constant = vm_constant
    @stats_reader = stats_reader
    freeze
  end

  # Whether this is the mode active in the given VM.
  def active?(ruby_vm = RubyVM)
    @detector.call(ruby_vm)
  end

  # Whether this Ruby can run the mode at all. ZJIT arrived in Ruby 4.0 and
  # YJIT can be left out of a build, so elsewhere the matching --flag is an
  # error rather than a slower run.
  def available?(ruby_vm = RubyVM)
    vm_constant.nil? || ruby_vm.const_defined?(vm_constant)
  end

  # What the JIT compiled and what it cost, normalized to keys that mean the
  # same thing across JITs. Distinguishes a JIT that compiled the hot methods
  # from one that bailed out and left the interpreter to do the work.
  def stats(ruby_vm = RubyVM)
    @stats_reader.call(ruby_vm)
  end

  def to_s
    label
  end

  # Whether a JIT constant exists on the VM and reports itself enabled.
  def self.jit_enabled?(ruby_vm, const_name)
    return false unless ruby_vm.const_defined?(const_name)

    jit = ruby_vm.const_get(const_name)
    jit.respond_to?(:enabled?) && jit.enabled?
  end

  # Maps one JIT's stat names onto the four shared keys.
  def self.normalize_stats(raw, compiled:, failed:, code_bytes:)
    {
      'compiled_iseq_count' => raw[compiled],
      'failed_iseq_count' => raw[failed],
      'compile_time_ns' => raw[:compile_time_ns],
      'code_region_bytes' => raw[code_bytes]
    }
  end

  NO_JIT = new(
    id: :none,
    cli_flags: %w[--disable-yjit].freeze,
    label: 'no JIT',
    column_label: 'no JIT',
    detector: ->(ruby_vm) { !jit_enabled?(ruby_vm, :YJIT) && !jit_enabled?(ruby_vm, :ZJIT) }
  )

  YJIT = new(
    id: :yjit,
    cli_flags: %w[--yjit].freeze,
    label: 'YJIT',
    column_label: 'YJIT',
    vm_constant: :YJIT,
    detector: ->(ruby_vm) { jit_enabled?(ruby_vm, :YJIT) },
    stats_reader: lambda { |ruby_vm|
      normalize_stats(ruby_vm.const_get(:YJIT).runtime_stats,
                      compiled: :compiled_iseq_count,
                      failed: :compilation_failure,
                      code_bytes: :code_region_size)
    }
  )

  ZJIT = new(
    id: :zjit,
    cli_flags: %w[--zjit].freeze,
    label: 'ZJIT',
    column_label: 'ZJIT',
    vm_constant: :ZJIT,
    detector: ->(ruby_vm) { jit_enabled?(ruby_vm, :ZJIT) },
    stats_reader: lambda { |ruby_vm|
      normalize_stats(ruby_vm.const_get(:ZJIT).stats,
                      compiled: :compiled_iseq_count,
                      failed: :failed_iseq_count,
                      code_bytes: :code_region_bytes)
    }
  )

  ALL = [NO_JIT, YJIT, ZJIT].freeze

  def self.fetch(id)
    ALL.find { |mode| mode.id == id.to_sym } ||
      raise(ArgumentError, "unknown Ruby mode #{id.inspect} (known: #{ALL.map(&:id).join(', ')})")
  end

  # The mode the given VM is running under. Detectors are mutually exclusive,
  # so exactly one matches.
  def self.active(ruby_vm = RubyVM)
    ALL.find { |mode| mode.active?(ruby_vm) }
  end

  # The mode named by the environment, or nil if it names none.
  def self.expected(env)
    id = env[ENV_VAR]
    id && fetch(id)
  end

  # Returns `actual`, or raises if it isn't what was expected.
  #
  # A Ruby that can't honor --yjit/--zjit only warns and falls back to the
  # interpreter, which would otherwise be measured and published under the
  # JIT's label.
  #
  # @param actual [RubyMode] what the VM reports
  # @param expected [RubyMode, nil] what was asked for; nil skips the check
  def self.verify!(actual:, expected:, ruby_description: RUBY_DESCRIPTION)
    return actual if expected.nil? || expected.equal?(actual)

    raise Mismatch,
          "expected to be running under #{expected.label} (#{ENV_VAR}=#{expected.id}) but the VM " \
          "reports #{actual.label} is active (#{ruby_description}) - was this Ruby built with " \
          'YJIT/ZJIT support?'
  end
end
