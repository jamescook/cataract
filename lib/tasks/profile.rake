# frozen_string_literal: true

namespace :profile do
  desc 'Profile pure Ruby parser with bootstrap.css (outputs JSON for speedscope)'
  task :parsing do
    require 'fileutils'

    # Check for stackprof
    begin
      require 'stackprof'
    rescue LoadError
      abort("stackprof gem not found. Install with: gem install stackprof")
    end

    # Ensure we're using pure Ruby implementation
    ENV['CATARACT_PURE'] = '1'

    fixture_path = File.expand_path('../../test/fixtures/bootstrap.css', __dir__)
    unless File.exist?(fixture_path)
      abort("Fixture not found: #{fixture_path}")
    end

    output_dir = 'tmp/profile'
    FileUtils.mkdir_p(output_dir)
    json_output = File.join(output_dir, 'stackprof-parsing.json')

    puts 'Profiling pure Ruby parser with bootstrap.css'
    puts '=' * 80
    puts "Fixture: #{fixture_path}"
    puts "Output:  #{json_output}"
    puts '=' * 80

    # Load the CSS content
    css_content = File.read(fixture_path)
    puts "CSS size: #{css_content.bytesize} bytes"
    puts

    require_relative '../../lib/cataract/pure'
    require 'json'

    # Use higher sampling rate (interval in microseconds, default is 1000)
    # Lower interval = higher sampling rate = more detailed profile
    profile = StackProf.run(mode: :wall, raw: true, interval: 100) do
      # Parse multiple times to get better signal
      10.times do
        Cataract.parse_css(css_content)
      end
    end

    # Write JSON output
    File.write(json_output, JSON.generate(profile))

    puts
    puts "Profile complete!"
    puts "JSON output: #{json_output}"
    puts
    puts "View in speedscope:"
    puts "  1. Visit https://www.speedscope.app/"
    puts "  2. Drag and drop: #{json_output}"
    puts
    puts "Or use stackprof CLI:"
    puts "  stackprof #{json_output} --text"
    puts "  stackprof #{json_output} --method 'Cataract'"
  end

  desc 'Profile pure Ruby flatten with bootstrap.css (outputs JSON for speedscope)'
  task :flatten do
    require 'fileutils'

    # Check for stackprof
    begin
      require 'stackprof'
    rescue LoadError
      abort('stackprof gem not found. Install with: gem install stackprof')
    end

    fixture_path = File.expand_path('../../test/fixtures/bootstrap.css', __dir__)
    unless File.exist?(fixture_path)
      abort("Fixture not found: #{fixture_path}")
    end

    output_dir = 'tmp/profile'
    FileUtils.mkdir_p(output_dir)
    json_output = File.join(output_dir, 'stackprof-flatten.json')

    puts "Profiling pure Ruby flatten with bootstrap.css"
    puts "=" * 80
    puts "Fixture: #{fixture_path}"
    puts "Output:  #{json_output}"
    puts "=" * 80

    # Load the CSS content
    css_content = File.read(fixture_path)
    puts "CSS size: #{css_content.bytesize} bytes"
    puts

    require_relative '../../lib/cataract/pure'
    require 'json'

    # Parse once outside profiling to get stylesheet
    stylesheet = Cataract.parse_css(css_content)
    puts "Parsed: #{stylesheet.rules.size} rules"
    puts

    # Profile flatten only
    # Use higher sampling rate (interval in microseconds, default is 1000)
    # Lower interval = higher sampling rate = more detailed profile
    profile = StackProf.run(mode: :wall, raw: true, interval: 100) do
      # Flatten multiple times to get better signal
      10.times do
        Cataract.flatten(stylesheet.dup)
      end
    end

    # Write JSON output
    File.write(json_output, JSON.generate(profile))

    puts
    puts "Profile complete!"
    puts "JSON output: #{json_output}"
    puts
    puts "View in speedscope:"
    puts "  1. Visit https://www.speedscope.app/"
    puts "  2. Drag and drop: #{json_output}"
    puts
    puts "Or use stackprof CLI:"
    puts "  stackprof #{json_output} --text"
    puts "  stackprof #{json_output} --method 'Cataract'"
  end

  desc 'Profile pure Ruby serialization with bootstrap.css (outputs JSON for speedscope)'
  task :serialization do
    require 'fileutils'

    # Check for stackprof
    begin
      require 'stackprof'
    rescue LoadError
      abort('stackprof gem not found. Install with: gem install stackprof')
    end

    # Ensure we're using pure Ruby implementation
    ENV['CATARACT_PURE'] = '1'

    fixture_path = File.expand_path('../../test/fixtures/bootstrap.css', __dir__)
    unless File.exist?(fixture_path)
      abort("Fixture not found: #{fixture_path}")
    end

    output_dir = 'tmp/profile'
    FileUtils.mkdir_p(output_dir)
    json_output = File.join(output_dir, 'stackprof-serialization.json')

    puts "Profiling pure Ruby serialization with bootstrap.css"
    puts "=" * 80
    puts "Fixture: #{fixture_path}"
    puts "Output:  #{json_output}"
    puts "=" * 80

    # Load the CSS content
    css_content = File.read(fixture_path)
    puts "CSS size: #{css_content.bytesize} bytes"
    puts

    require_relative '../../lib/cataract/pure'
    require 'json'

    # Parse once outside profiling to get stylesheet
    stylesheet = Cataract.parse_css(css_content)
    puts "Parsed: #{stylesheet.rules.size} rules"
    puts

    # Profile serialization only (to_s)
    # Use higher sampling rate (interval in microseconds, default is 1000)
    # Lower interval = higher sampling rate = more detailed profile
    profile = StackProf.run(mode: :wall, raw: true, interval: 100) do
      # Serialize multiple times to get better signal
      10.times do
        stylesheet.to_s
      end
    end

    # Write JSON output
    File.write(json_output, JSON.generate(profile))

    puts
    puts "Profile complete!"
    puts "JSON output: #{json_output}"
    puts
    puts "View in speedscope:"
    puts "  1. Visit https://www.speedscope.app/"
    puts "  2. Drag and drop: #{json_output}"
    puts
    puts "Or use stackprof CLI:"
    puts "  stackprof #{json_output} --text"
    puts "  stackprof #{json_output} --method 'Cataract'"
  end
end

desc 'Profile pure Ruby parser, flatten, and serialization (outputs JSON for speedscope)'
task profile: ['profile:parsing', 'profile:flatten', 'profile:serialization'] do
  puts
  puts "=" * 80
  puts "All profiles complete!"
  puts "Artifacts in: tmp/profile/"
  puts "  - stackprof-parsing.json"
  puts "  - stackprof-flatten.json"
  puts "  - stackprof-serialization.json"
  puts "=" * 80
end
