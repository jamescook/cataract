# frozen_string_literal: true

require 'test_helper'
require_relative '../benchmarks/worker_helpers'

class TestWorkerHelpers < Minitest::Test
  class Worker
    include WorkerHelpers

    def self.benchmark_name
      'serialization'
    end

    def initialize(implementation)
      @implementation = implementation
    end
  end

  def setup
    @zjit = Worker.new(Implementation.find(:pure, :zjit))
    @native = Worker.new(Implementation.find(:native, :none))
  end

  def test_result_filename_is_scoped_to_the_variant
    assert_equal 'serialization_pure_zjit', @zjit.benchmark_name
    assert_equal 'serialization_native_none', @native.benchmark_name
  end

  def test_report_names_follow_the_label_colon_id_convention
    assert_equal 'cataract pure: bootstrap_compact', @zjit.result_name('bootstrap_compact')
    assert_equal 'cataract: bootstrap_compact', @native.result_name('bootstrap_compact')
  end

  def test_report_names_omit_the_jit_because_results_carry_it_as_a_field
    id = 'selector lists'

    assert_equal Worker.new(Implementation.find(:pure, :yjit)).result_name(id),
                 Worker.new(Implementation.find(:pure, :zjit)).result_name(id)
  end
end
