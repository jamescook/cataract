# frozen_string_literal: true

# The part of Minitest this suite uses, in Ruby that Spinel can compile.
#
# Minitest finds test classes and methods by reflection and runs them through
# `send`, neither of which exists in an ahead-of-time compiled program. Under
# `rake test:spinel` the test files are compiled as they are, against this
# file instead of Minitest, and a generated program calls each test method by
# name (see lib/tasks/spinel.rake). Only the assertions live here; a test file
# should not be able to tell the difference.
#
# Messages follow Minitest's wording where a test could plausibly read them.
#
# The Minitest cops are off for this file: they tell a test to call the
# assertion this file is the definition of.
# rubocop:disable-next Minitest, Naming/PredicateMethod, Style/CaseEquality, Style/ClassEqualityComparison
module Minitest
  # A failed assertion. Not a StandardError, as in Minitest, so a test's own
  # `rescue => e` does not swallow it.
  class Assertion < Exception; end # rubocop:disable Lint/InheritException

  # Raised by #skip.
  class Skip < Assertion; end

  class Test
    attr_accessor :assertions

    def setup; end

    def teardown; end

    def flunk(msg = nil)
      raise Minitest::Assertion, (msg || 'Epic Fail!')
    end

    def skip(msg = nil)
      raise Minitest::Skip, (msg || 'Skipped, no message given')
    end

    def pass(_msg = nil)
      count_assertion
      true
    end

    def assert(test, msg = nil)
      count_assertion
      raise Minitest::Assertion, (msg || 'Expected a truthy value, got a falsy one') unless test

      true
    end

    def refute(test, msg = nil)
      count_assertion
      raise Minitest::Assertion, (msg || 'Expected a falsy value, got a truthy one') if test

      true
    end

    def assert_equal(exp, act, msg = nil)
      assert exp == act, msg || "Expected: #{exp.inspect}\n  Actual: #{act.inspect}"
    end

    def refute_equal(exp, act, msg = nil)
      refute exp == act, msg || "Expected #{act.inspect} to not be equal to #{exp.inspect}"
    end

    def assert_nil(obj, msg = nil)
      assert obj.nil?, msg || "Expected #{obj.inspect} to be nil"
    end

    def refute_nil(obj, msg = nil)
      refute obj.nil?, msg || 'Expected nil to not be nil'
    end

    def assert_same(exp, act, msg = nil)
      assert exp.equal?(act), msg || "Expected #{act.inspect} to be the same object as #{exp.inspect}"
    end

    def refute_same(exp, act, msg = nil)
      refute exp.equal?(act), msg || "Expected #{act.inspect} to not be the same object as #{exp.inspect}"
    end

    def assert_empty(obj, msg = nil)
      assert obj.empty?, msg || "Expected #{obj.inspect} to be empty"
    end

    def refute_empty(obj, msg = nil)
      refute obj.empty?, msg || "Expected #{obj.inspect} to not be empty"
    end

    def assert_includes(collection, obj, msg = nil)
      assert collection.include?(obj), msg || "Expected #{collection.inspect} to include #{obj.inspect}"
    end

    def refute_includes(collection, obj, msg = nil)
      refute collection.include?(obj), msg || "Expected #{collection.inspect} to not include #{obj.inspect}"
    end

    # `cls === obj` rather than `obj.is_a?(cls)` here and below: Spinel refuses
    # is_a? with a class it only knows at run time, and answers === the way
    # CRuby does, modules included.
    def assert_kind_of(cls, obj, msg = nil)
      assert cls === obj, msg || "Expected #{obj.inspect} to be a kind of #{cls}, not #{obj.class}"
    end

    def assert_instance_of(cls, obj, msg = nil)
      assert obj.class == cls, msg || "Expected #{obj.inspect} to be an instance of #{cls}, not #{obj.class}"
    end

    def assert_respond_to(obj, meth, msg = nil)
      assert obj.respond_to?(meth), msg || "Expected #{obj.inspect} (#{obj.class}) to respond to ##{meth}"
    end

    def assert_match(matcher, obj, msg = nil)
      matched = matcher.is_a?(String) ? obj.include?(matcher) : matcher.match?(obj)

      assert matched, msg || "Expected #{matcher.inspect} to match #{obj.inspect}"
    end

    def refute_match(matcher, obj, msg = nil)
      matched = matcher.is_a?(String) ? obj.include?(matcher) : matcher.match?(obj)

      refute matched, msg || "Expected #{matcher.inspect} to not match #{obj.inspect}"
    end

    def assert_in_delta(exp, act, delta = 0.001, msg = nil)
      difference = (exp - act).abs

      assert delta >= difference, msg || "Expected |#{exp} - #{act}| (#{difference}) to be <= #{delta}"
    end

    def assert_operator(left, operator, right, msg = nil)
      assert left.__send__(operator, right), msg || "Expected #{left.inspect} to be #{operator} #{right.inspect}"
    end

    def assert_predicate(obj, predicate, msg = nil)
      assert obj.__send__(predicate), msg || "Expected #{obj.inspect} to be #{predicate}"
    end

    def refute_predicate(obj, predicate, msg = nil)
      refute obj.__send__(predicate), msg || "Expected #{obj.inspect} to not be #{predicate}"
    end

    def assert_path_exists(path, msg = nil)
      assert File.exist?(path), msg || "Expected path '#{path}' to exist"
    end

    def refute_path_exists(path, msg = nil)
      refute File.exist?(path), msg || "Expected path '#{path}' to not exist"
    end

    # Runs the block and returns the exception it raised, which has to be one
    # of the given classes (StandardError when none is given).
    def assert_raises(*expected)
      count_assertion
      raised = nil
      begin
        yield
      rescue Minitest::Skip
        raise
      rescue Exception => e # rubocop:disable Lint/RescueException
        raised = e
      end

      raise Minitest::Assertion, "#{describe_classes(expected)} expected but nothing was raised." if raised.nil?

      wanted = expected.empty? ? [StandardError] : expected
      return raised if wanted.any? { |cls| cls === raised }

      raise Minitest::Assertion,
            "#{describe_classes(expected)} expected, not #{raised.class}: #{raised.message}"
    end

    private

    def count_assertion
      @assertions = (@assertions || 0) + 1
    end

    def describe_classes(classes)
      classes.empty? ? 'StandardError' : classes.join(', ')
    end
  end

  # Runs test methods and keeps the tally. The generated program hands each
  # test to #run as a block that builds the test object and calls the method.
  class SpinelRunner
    attr_reader :runs, :assertions, :failures, :errors, :skips

    def initialize
      @runs = 0
      @assertions = 0
      @failures = 0
      @errors = 0
      @skips = 0
    end

    def count_assertions(test)
      @assertions += test.assertions || 0
    end

    def passed
      @runs += 1
    end

    def skipped(name, error)
      @runs += 1
      @skips += 1
      puts "SKIP\t#{name}\t#{first_line(error.message)}"
    end

    def failed(name, error)
      @runs += 1
      @failures += 1
      puts "FAIL\t#{name}\t#{first_line(error.message)}"
    end

    def errored(name, error)
      @runs += 1
      @errors += 1
      puts "ERROR\t#{name}\t#{error.class}: #{first_line(error.message)}"
    end

    def summary
      puts "SUMMARY\t#{@runs}\t#{@assertions}\t#{@failures}\t#{@errors}\t#{@skips}"
    end

    private

    def first_line(message)
      message.to_s.split("\n").first.to_s
    end
  end
end
