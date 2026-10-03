# frozen_string_literal: true

require 'test_helper'
require_relative '../benchmarks/spinel_worker'
require_relative '../benchmarks/result_set'

# Covers turning a compiled benchmark's output into result rows. The output
# format is produced by benchmarks/spinel/measure.rb, which is ordinary Ruby,
# so it is exercised here under CRuby rather than assumed.
class TestSpinelWorker < Minitest::Test
  OUTPUT = <<~TEXT
    engine\tspinel
    result\tsmall\t29759.5\t4110.25\t145860\t4420\t5.5
    result\tselector lists (disabled)\t1369.5\t168.5\t6731\t127\t5.0
  TEXT

  def rows
    SpinelWorker.rows(OUTPUT)
  end

  def test_one_row_per_result_line
    assert_equal 2, rows.size
  end

  def test_rows_are_named_label_colon_id_like_every_other_implementations
    assert_equal ['small', 'selector lists (disabled)'], rows.map { |row| ResultSet.test_case_id(row) }
    assert_equal 'cataract spinel: small', rows.first['name']
  end

  def test_rows_carry_the_keys_benchmark_ips_writes
    row = rows.first

    assert_in_delta 29_759.5, row['central_tendency']
    assert_in_delta 29_759.5, row['ips']
    assert_in_delta 4110.25, row['stddev']
    assert_in_delta 4110.25, row['error']
    assert_in_delta 5_500_000.0, row['microseconds']
    assert_equal 145_860, row['iterations']
    assert_equal 4420, row['cycles']
  end

  def test_rows_are_stamped_as_the_spinel_implementation
    row = rows.first

    assert_equal 'spinel_none', row['implementation']
    assert_equal 'spinel', row['backend']
    assert_equal 'none', row['jit']
    assert_empty row['jit_stats']
  end

  def test_refuses_output_from_a_program_spinel_did_not_compile
    # The program is plain Ruby and runs under CRuby too; its numbers must
    # not be published as Spinel's.
    error = assert_raises(SpinelWorker::Mismatch) { SpinelWorker.rows(OUTPUT.sub('spinel', 'ruby')) }

    assert_match(/"ruby"/, error.message)
  end

  def test_refuses_output_that_does_not_say_what_produced_it
    assert_raises(SpinelWorker::Mismatch) { SpinelWorker.rows("result\tsmall\t1.0\t0.0\t1\t1\t1.0\n") }
  end

  def test_measure_prints_the_line_the_worker_reads
    require_relative '../benchmarks/spinel/measure'

    output, = capture_io do
      SpinelBench.header
      SpinelBench.measure('tiny', 0.0, 0.01) { 1 + 1 }
    end
    engine, result = output.lines.map { |line| line.chomp.split("\t") }

    assert_equal ['engine', RUBY_ENGINE], engine
    assert_equal %w[result tiny], result.first(2)
    assert_equal 7, result.size
    assert_operator result[2].to_f, :>, 0
  end

  # The compiled programs repeat the benchmark's test case ids as literals,
  # where the Ruby workers take them from the metadata. An id that drifts
  # would put a Spinel measurement in no row of BENCHMARKS.md, silently.
  def test_the_compiled_parsing_and_serialization_programs_name_every_test_case
    require_relative '../benchmarks/parsing_tests'
    require_relative '../benchmarks/serialization_tests'

    { 'parsing' => ParsingTests.metadata, 'serialization' => SerializationTests.metadata }.each do |name, metadata|
      source = File.read(File.expand_path("../benchmarks/spinel/#{name}.rb", __dir__))
      ids = metadata.values.flatten.map { |test_case| test_case['id'] }

      ids.each do |id|
        assert_match(/measure\('#{Regexp.escape(id)}'/, source, "#{name}.rb does not measure #{id.inspect}")
      end
    end
  end
end
