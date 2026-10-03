# frozen_string_literal: true

require 'open3'

# The Spinel ahead-of-time compiler, as far as the harness needs it: found,
# and asked to turn one Ruby program into one executable.
#
# Looked up the way Spinel's own tools look it up - $SPINEL (the compiler
# itself), then $SPINEL_DIR/spinel, then `spinel` on PATH - so a checkout that
# was never installed works by pointing one variable at it.
#
# The environment is passed in rather than read globally, so the lookup is
# testable without a compiler on the machine.
class SpinelCompiler
  class CompileError < StandardError
  end

  # @param env [Hash] environment to look the compiler up in
  # @return [SpinelCompiler, nil] nil when there is no compiler to find
  def self.locate(env = ENV)
    path = candidates(env).find { |candidate| File.file?(candidate) && File.executable?(candidate) }
    path && new(path)
  end

  # Every place a compiler could be, most specific first.
  def self.candidates(env)
    on_path = env.fetch('PATH', '').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'spinel') }
    explicit = [env['SPINEL'], env['SPINEL_DIR'] && File.join(env['SPINEL_DIR'], 'spinel')]

    [*explicit, *on_path].compact.reject(&:empty?)
  end

  attr_reader :path

  def initialize(path)
    @path = path
    freeze
  end

  # e.g. "spinel 2026.09.12+4725 (0919a4b0b) [apple clang 21.0.0 (cc)]"
  def version
    stdout, _stderr, status = Open3.capture3(path, '--version')
    status.success? ? stdout.lines.first.to_s.strip : 'spinel (unknown version)'
  end

  # Compiles a Ruby program into an executable.
  #
  # --require-gate makes a `require` Spinel cannot satisfy an error instead of
  # a warning, as it is under `spin build` - a program that silently dropped a
  # library would not be the program that was asked for.
  #
  # @param source [String] the program's entry file
  # @param output [String] where to write the executable
  # @param load_path [String, Array<String>] roots a `require` resolves against
  # @param flags [Array<String>] further compiler flags
  # @return [String] output
  def compile(source, output:, load_path:, flags: [])
    roots = Array(load_path).flat_map { |dir| ['-I', dir] }
    command = [path, '--require-gate', *flags, *roots, source, '-o', output]
    stdout, stderr, status = Open3.capture3(*command)
    return output if status.success?

    raise CompileError, "#{command.join(' ')} failed:\n#{stderr.empty? ? stdout : stderr}"
  end

  def to_s
    path
  end
end
