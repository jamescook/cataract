# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../benchmarks/spinel_compiler'

# Covers finding the compiler and reporting a failed compile. Nothing here
# needs a real Spinel: the lookup takes its environment as a value, and a
# shell script stands in for the compiler.
class TestSpinelCompiler < Minitest::Test
  def setup
    @dir = Dir.mktmpdir
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def executable(name, body = "#!/bin/sh\nexit 0\n")
    path = File.join(@dir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    File.chmod(0o755, path)
    path
  end

  def test_locate_is_nil_when_there_is_no_compiler
    assert_nil SpinelCompiler.locate({})
    assert_nil SpinelCompiler.locate('PATH' => @dir)
  end

  def test_locate_finds_the_compiler_named_by_spinel
    path = executable('my-spinel')

    assert_equal path, SpinelCompiler.locate('SPINEL' => path).path
  end

  def test_locate_finds_spinel_in_the_directory_named_by_spinel_dir
    path = executable('checkout/spinel')

    assert_equal path, SpinelCompiler.locate('SPINEL_DIR' => File.join(@dir, 'checkout')).path
  end

  def test_locate_finds_spinel_on_path
    path = executable('bin/spinel')

    assert_equal path, SpinelCompiler.locate('PATH' => ['/nonexistent', File.join(@dir, 'bin')].join(File::PATH_SEPARATOR)).path
  end

  def test_locate_prefers_the_explicit_variable_over_path
    explicit = executable('explicit/spinel')
    executable('bin/spinel')

    located = SpinelCompiler.locate('SPINEL' => explicit, 'PATH' => File.join(@dir, 'bin'))

    assert_equal explicit, located.path
  end

  def test_locate_ignores_a_file_that_is_not_executable
    path = File.join(@dir, 'spinel')
    File.write(path, '')

    assert_nil SpinelCompiler.locate('SPINEL' => path)
  end

  def test_compile_passes_the_gate_the_load_paths_and_the_output
    log = File.join(@dir, 'args')
    compiler = SpinelCompiler.new(executable('spinel', "#!/bin/sh\necho \"$@\" > #{log}\n"))

    output = compiler.compile('prog.rb', output: 'prog', load_path: %w[lib test], flags: ['--defer-refusals'])

    assert_equal 'prog', output
    assert_equal '--require-gate --defer-refusals -I lib -I test prog.rb -o prog', File.read(log).strip
  end

  def test_compile_raises_with_what_the_compiler_said
    compiler = SpinelCompiler.new(executable('spinel', "#!/bin/sh\necho 'spinel: 2 refusals' >&2\nexit 1\n"))

    error = assert_raises(SpinelCompiler::CompileError) do
      compiler.compile('prog.rb', output: 'prog', load_path: 'lib')
    end

    assert_match(/spinel: 2 refusals/, error.message)
  end
end
