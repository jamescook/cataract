# frozen_string_literal: true

require_relative 'backend'
require_relative 'ruby_mode'

# One benchmarked configuration: a Backend paired with the RubyMode it runs
# under.
#
# Orchestrators launch one subprocess per Implementation, workers stamp their
# results with the one they ran as, and BENCHMARKS.md renders one column per
# Implementation. The two axes are carried separately through results, so
# nothing downstream takes an id apart to recover them.
class Implementation
  attr_reader :backend, :mode

  def initialize(backend:, mode:)
    @backend = backend
    @mode = mode
    freeze
  end

  # Every backend crossed with the modes it declares.
  def self.all
    Backend::ALL.flat_map do |backend|
      backend.modes.map { |mode| new(backend: backend, mode: mode) }
    end
  end

  def self.find(backend_id, mode_id)
    new(backend: Backend.fetch(backend_id), mode: RubyMode.fetch(mode_id))
  end

  # What a process is running as, verified on both axes against what was
  # asked for. Raises rather than return a mislabeled configuration.
  #
  # The only place the ambient facts are read; everything below takes them as
  # values.
  def self.current(env: ENV, backend: Backend.active, mode: RubyMode.active)
    new(
      backend: Backend.verify!(actual: backend, expected: Backend.expected(env)),
      mode: RubyMode.verify!(actual: mode, expected: RubyMode.expected(env))
    )
  end

  # Identifier for result filenames and for matching a result to its column.
  def id
    :"#{backend.id}_#{mode.id}"
  end

  # Console label, e.g. "cataract pure (ZJIT)".
  def label
    qualify(backend.label, mode.label)
  end

  # BENCHMARKS.md column heading, e.g. "Pure (ZJIT)".
  def column_label
    qualify(backend.column_label, mode.column_label)
  end

  def ruby_command(script)
    ['ruby', *mode.cli_flags, script]
  end

  def env
    backend.selection_env.merge(
      Backend::ENV_VAR => backend.id.to_s,
      RubyMode::ENV_VAR => mode.id.to_s
    )
  end

  # Fields stamped onto every result row. `backend` and `jit` are what
  # consumers filter on.
  def result_fields
    {
      'implementation' => id.to_s,
      'backend' => backend.id.to_s,
      'jit' => mode.id.to_s
    }
  end

  # Whether the given result row came from this implementation.
  def produced?(result)
    result['implementation'] == id.to_s
  end

  def ==(other)
    other.is_a?(Implementation) && other.backend == backend && other.mode == mode
  end
  alias eql? ==

  def hash
    [backend, mode].hash
  end

  def to_s
    label
  end

  private

  # Appends the mode only when the backend runs under more than one.
  def qualify(base, suffix)
    backend.modes.one? ? base : "#{base} (#{suffix})"
  end
end
