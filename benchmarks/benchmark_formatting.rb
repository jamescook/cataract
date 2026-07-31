# frozen_string_literal: true

# Shared presentation of benchmark numbers for BENCHMARKS.md.
module BenchmarkFormatting
  # Cell content when an implementation has no measurement for a test case.
  MISSING = 'N/A'

  def format_ips(result, short: false)
    return MISSING unless result

    ips = result['central_tendency']
    formatted = if ips >= 1_000_000
                  "#{(ips / 1_000_000.0).round(2)}M"
                elsif ips >= 1_000
                  "#{(ips / 1_000.0).round(2)}K"
                else
                  ips.round(1).to_s
                end

    short ? "#{formatted} i/s" : "#{formatted} i/s (#{format_time_per_op(result)})"
  end

  def format_time_per_op(result)
    time_us = 1_000_000.0 / result['central_tendency']

    if time_us >= 1_000
      "#{(time_us / 1_000).round(2)} ms"
    else
      "#{time_us.round(2)} μs"
    end
  end

  # Renders a ratio as "Nx faster" or, below 1, its reciprocal as "Nx
  # slower".
  def format_speedup(speedup)
    return MISSING if speedup.nil?
    return "#{speedup.round(2)}x faster" if speedup >= 1

    "#{(1.0 / speedup).round(2)}x slower"
  end

  # Cost of enabling a feature, as a percentage of the rate without it.
  def format_overhead(without, with)
    return MISSING unless without && with

    slowdown = ((without['central_tendency'] / with['central_tendency']) - 1) * 100

    if slowdown.abs < 1.0
      '~0% (within noise)'
    elsif slowdown.negative?
      format('%.1f%% faster (unexpected)', slowdown.abs)
    else
      format('%.1f%% slower', slowdown)
    end
  end
end
