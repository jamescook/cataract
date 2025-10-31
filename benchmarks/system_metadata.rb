# frozen_string_literal: true

require 'json'
require 'fileutils'

# Collects system metadata for benchmark runs
class SystemMetadata
  RESULTS_DIR = File.expand_path('.results', __dir__)

  def self.collect
    metadata = {
      'ruby_version' => RUBY_VERSION,
      'ruby_description' => RUBY_DESCRIPTION,
      'platform' => RUBY_PLATFORM,
      'cpu' => detect_cpu,
      'memory' => detect_memory,
      'os' => detect_os,
      'timestamp' => Time.now.iso8601
    }

    FileUtils.mkdir_p(RESULTS_DIR)
    File.write(File.join(RESULTS_DIR, 'metadata.json'), JSON.pretty_generate(metadata))

    metadata
  end

  def self.detect_cpu
    if RUBY_PLATFORM.include?('darwin')
      `sysctl -n machdep.cpu.brand_string`.strip
    elsif File.exist?('/proc/cpuinfo')
      cpuinfo = File.read('/proc/cpuinfo')
      if (match = cpuinfo.match(/model name\s*:\s*(.+)/))
        match[1].strip
      else
        'Unknown'
      end
    else
      'Unknown'
    end
  rescue StandardError
    'Unknown'
  end

  def self.detect_memory
    if RUBY_PLATFORM.include?('darwin')
      # Output in GB
      bytes = `sysctl -n hw.memsize`.strip.to_i
      "#{bytes / (1024 * 1024 * 1024)}GB"
    elsif File.exist?('/proc/meminfo')
      meminfo = File.read('/proc/meminfo')
      if (match = meminfo.match(/MemTotal:\s+(\d+)\s+kB/))
        kb = match[1].to_i
        "#{(kb / (1024 * 1024))}GB"
      else
        'Unknown'
      end
    else
      'Unknown'
    end
  rescue StandardError
    'Unknown'
  end

  def self.detect_os
    if RUBY_PLATFORM.include?('darwin')
      version = `sw_vers -productVersion`.strip
      "macOS #{version}"
    elsif File.exist?('/etc/os-release')
      os_release = File.read('/etc/os-release')
      if (match = os_release.match(/PRETTY_NAME="(.+)"/))
        match[1]
      else
        RUBY_PLATFORM
      end
    else
      RUBY_PLATFORM
    end
  rescue StandardError
    RUBY_PLATFORM
  end
end
