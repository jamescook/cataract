# frozen_string_literal: true

require 'etc'
require 'open3'
require 'tmpdir'
require_relative '../../benchmarks/spinel_compiler'

# Runs the Minitest suite as programs compiled by Spinel (`rake test:spinel`).
#
# The test files are the ones the pure Ruby suite runs, unchanged. What
# differs is how they are run, because a compiled program has neither
# Minitest nor reflection:
#
# - the tests are discovered here, under CRuby, by loading the files and
#   asking Minitest what it would run;
# - each test file becomes one generated program that calls its tests by
#   name, against the assertions in spinel_minitest.rb;
# - each program is compiled and run on its own, so a file Spinel cannot
#   build costs that file's tests rather than the whole suite.
#
# A file is compiled with --defer-refusals: a method Spinel refuses raises
# NotImplementedError when called, so one construct it cannot compile fails
# the tests that reach it instead of the whole file.
class SpinelTestSuite
  ROOT = File.expand_path('../..', __dir__)
  # test/support/spinel comes first so `require 'minitest/autorun'` and
  # `require 'webmock/minitest'` in a test file find the stand-ins there.
  LOAD_PATH = [File.join(ROOT, 'lib'), File.join(ROOT, 'test/support/spinel'), File.join(ROOT, 'test')].freeze

  # What `rake test:pure` sets, and a test may check for.
  ENVIRONMENT = { 'CATARACT_PURE' => '1' }.freeze

  # One test file's outcome. `problem` is set when the file never produced a
  # tally of its own: it did not compile, or its program died.
  Result = Struct.new(:file, :tests, :runs, :assertions, :failures, :errors, :skips, :lines, :problem) do
    def unaccounted
      tests - runs
    end
  end

  # Prints, for every test Minitest would run, "file\tclass\tmethod". Loaded
  # in a process of its own, with Minitest told not to run anything. The test
  # methods are read off the class rather than asked for with
  # runnable_methods, which shuffles them and wants a seed to do it.
  DISCOVER = <<~'RUBY'
    require 'minitest'
    def Minitest.autorun; end
    require 'test_helper'
    ARGV.each { |file| require File.expand_path(file) }
    Minitest::Runnable.runnables.each do |klass|
      klass.public_instance_methods(true).grep(/\Atest_/).each do |name|
        puts [klass.instance_method(name).source_location.first, klass.name, name].join("\t")
      end
    end
  RUBY

  # @param files [Array<String>] test files, as the pure suite lists them
  # @param compiler [SpinelCompiler, nil]
  # @param jobs [Integer] programs compiled and run at once
  def initialize(files:, compiler: SpinelCompiler.locate(ENV), jobs: Etc.nprocessors, out: $stdout)
    @files = files.map { |file| File.expand_path(file, ROOT) }
    @compiler = compiler
    @jobs = jobs
    @out = out
  end

  # @return [Boolean] whether every test ran and passed
  def run
    abort 'No Spinel compiler found: set SPINEL to the compiler or SPINEL_DIR to its directory.' unless @compiler

    tests = discover
    @out.puts "Compiling #{tests.size} test files (#{tests.values.sum(&:size)} tests) with #{@compiler.version}"

    results = Dir.mktmpdir('cataract-spinel-tests') { |dir| run_all(tests, dir) }
    report(results)
  end

  # @return [Hash{String => Array<Array(String, String)>}] file => [class, method] pairs
  def discover
    command = ['ruby', '-I', File.join(ROOT, 'lib'), '-I', File.join(ROOT, 'test'), '-e', DISCOVER, *@files]
    stdout, stderr, status = Open3.capture3(ENVIRONMENT, *command, chdir: ROOT)
    raise "could not list the suite's tests:\n#{stderr}" unless status.success?

    stdout.lines.map { |line| line.chomp.split("\t") }
          .group_by(&:first)
          .transform_values { |rows| rows.map { |_file, klass, name| [klass, name] }.sort }
          .sort.to_h
  end

  # The program for one test file: test_helper (which the rake task loads
  # with -r for the other suites, so a test file need not), the file itself,
  # then one method per test so each test object keeps its own class's type,
  # then the calls.
  def program(file, tests)
    methods = tests.each_with_index.map do |(klass, name), index|
      <<~RUBY
        def spinel_test_#{index}(runner)
          test = #{klass}.new
          begin
            test.setup
            test.#{name}
            runner.passed
          rescue Minitest::Skip => e
            runner.skipped('#{klass}##{name}', e)
          rescue Minitest::Assertion => e
            runner.failed('#{klass}##{name}', e)
          rescue Exception => e
            runner.errored('#{klass}##{name}', e)
          ensure
            test.teardown
            runner.count_assertions(test)
          end
        end
      RUBY
    end

    calls = tests.each_index.map { |index| "spinel_test_#{index}(runner)" }

    [
      "require 'test_helper'", "require_relative '#{file}'", '', *methods,
      'runner = Minitest::SpinelRunner.new', *calls, 'runner.summary', ''
    ].join("\n")
  end

  private

  def run_all(tests, dir)
    queue = Queue.new
    tests.each_with_index { |pair, index| queue << [*pair, index] }
    results = Queue.new

    workers = Array.new([@jobs, tests.size].min) do
      Thread.new do
        loop do
          file, file_tests, index = queue.pop(true)
          result = run_file(file, file_tests, File.join(dir, index.to_s))
          results << result
          @out.puts progress_line(result)
        rescue ThreadError
          break
        end
      end
    end
    workers.each(&:join)

    Array.new(results.size) { results.pop }.sort_by(&:file)
  end

  def run_file(file, tests, path)
    result = Result.new(relative(file), tests.size, 0, 0, 0, 0, 0, [], nil)
    File.write("#{path}.rb", program(file, tests))

    begin
      @compiler.compile("#{path}.rb", output: path, load_path: LOAD_PATH, flags: ['--defer-refusals'])
    rescue SpinelCompiler::CompileError => e
      result.problem = "did not compile: #{first_diagnostic(e.message)}"
      return result
    end

    stdout, stderr, status = Open3.capture3(ENVIRONMENT, path, chdir: ROOT)
    tally(result, stdout)
    result.problem = "died (#{describe(status)}): #{stderr.lines.last.to_s.strip}" unless status.success? && result.runs.positive?
    result
  end

  def tally(result, stdout)
    stdout.each_line do |line|
      kind, *fields = line.chomp.split("\t")

      case kind
      when 'FAIL', 'ERROR', 'SKIP'
        result.lines << [kind, *fields]
      when 'SUMMARY'
        result.runs, result.assertions, result.failures, result.errors, result.skips = fields.map(&:to_i)
      end
    end
  end

  def progress_line(result)
    status = if result.problem
               'BROKEN'
             elsif (result.failures + result.errors).zero?
               'ok'
             else
               "#{result.failures + result.errors} failing"
             end

    format('  %-58<file>s %4<tests>d tests  %<status>s', file: result.file, tests: result.tests, status: status)
  end

  def report(results) # rubocop:disable Naming/PredicateMethod
    broken = results.select(&:problem)
    unless broken.empty?
      @out.puts "\nFiles that produced no result:"
      broken.each { |result| @out.puts "  #{result.file} (#{result.tests} tests) #{result.problem}" }
    end

    report_tests(results, 'FAIL', 'Failures')
    report_tests(results, 'ERROR', 'Errors')

    tests = results.sum(&:tests)
    unaccounted = results.sum(&:unaccounted)
    totals = %i[runs assertions failures errors skips].to_h { |field| [field, results.sum(&field)] }

    @out.puts format("\n%<runs>d runs, %<assertions>d assertions, %<failures>d failures, %<errors>d errors, %<skips>d skips",
                     totals)
    @out.puts "#{unaccounted} of #{tests} tests did not run (#{broken.size} files produced no result)" if unaccounted.positive?

    unaccounted.zero? && totals[:failures].zero? && totals[:errors].zero?
  end

  def report_tests(results, kind, heading)
    lines = results.flat_map { |result| result.lines.select { |line| line.first == kind } }
    return if lines.empty?

    @out.puts "\n#{heading}:"
    lines.each { |_kind, name, message| @out.puts "  #{name}\n    #{message}" }
  end

  # The first thing the compiler said that is not a warning.
  def first_diagnostic(message)
    line = message.lines.drop(1).find { |candidate| !candidate.include?('warning:') } || message.lines.last
    line.to_s.strip.sub("#{ROOT}/", '')[0, 220]
  end

  def describe(status)
    status.signaled? ? "signal #{status.termsig}" : "exit #{status.exitstatus}"
  end

  def relative(file)
    file.sub("#{ROOT}/", '')
  end
end
