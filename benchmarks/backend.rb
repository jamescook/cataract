# frozen_string_literal: true

require_relative 'ruby_mode'

# A Cataract implementation under test: pure Ruby or the C extension.
#
# Each backend declares which RubyModes it is benchmarked under. The C
# extension declares only one - a JIT doesn't compile its code, so further
# modes would resample the same number.
class Backend
  # Read by Cataract at require time to pick a backend.
  SELECTION_ENV_VAR = 'CATARACT_PURE'

  # Set by a parent process to declare which backend a worker should load.
  ENV_VAR = 'CATARACT_BENCH_BACKEND'

  Mismatch = Class.new(StandardError)

  attr_reader :id, :label, :column_label, :modes, :selection_env

  def initialize(id:, label:, column_label:, modes:, selection_env:)
    @id = id
    @label = label
    @column_label = column_label
    @modes = modes.freeze
    @selection_env = selection_env.freeze
    freeze
  end

  def to_s
    label
  end

  NATIVE = new(
    id: :native,
    label: 'cataract',
    column_label: 'Native',
    modes: [RubyMode::NO_JIT].freeze,
    selection_env: { SELECTION_ENV_VAR => nil }.freeze
  )

  PURE = new(
    id: :pure,
    label: 'cataract pure',
    column_label: 'Pure',
    modes: [RubyMode::NO_JIT, RubyMode::YJIT, RubyMode::ZJIT].freeze,
    selection_env: { SELECTION_ENV_VAR => '1' }.freeze
  )

  # Drives both the order variants run in and the column order in
  # BENCHMARKS.md.
  ALL = [NATIVE, PURE].freeze

  def self.fetch(id)
    ALL.find { |backend| backend.id == id.to_sym } ||
      raise(ArgumentError, "unknown backend #{id.inspect} (known: #{ALL.map(&:id).join(', ')})")
  end

  # The backend behind a loaded Cataract.
  #
  # @param loaded [Symbol] the value of Cataract::IMPLEMENTATION
  def self.active(loaded = Cataract::IMPLEMENTATION)
    loaded == :ruby ? PURE : NATIVE
  end

  # The backend named by the environment, or nil if it names none.
  def self.expected(env)
    id = env[ENV_VAR]
    id && fetch(id)
  end

  # Returns `actual`, or raises if it isn't what was expected.
  def self.verify!(actual:, expected:)
    return actual if expected.nil? || expected.equal?(actual)

    raise Mismatch,
          "expected to have loaded the #{expected.label} backend (#{ENV_VAR}=#{expected.id}) but " \
          "Cataract::IMPLEMENTATION reports #{actual.label} is loaded"
  end
end
