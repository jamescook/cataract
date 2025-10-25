# Shared Ragel generation logic used by both Rakefile and extconf.rb
module RagelGenerator
  def self.generate_c_from_ragel(ext_dir: 'ext/cataract', ragel_style: nil)
    # Check if ragel is installed
    ragel_version = `ragel --version 2>/dev/null`
    unless $?.success?
      abort("Ragel not found. Install with: brew install ragel (macOS) or apt-get install ragel (Ubuntu)")
    end
    puts "Found Ragel: #{ragel_version.strip}"

    ragel_style ||= ENV['RAGEL_STYLE'] || '-T0'
    ragel_flags = "#{ragel_style} -C"

    ragel_files = [
      ['cataract.rl', 'cataract.c'],
      ['shorthand_expander.rl', 'shorthand_expander.c']
    ]

    ragel_files.each do |rl_name, c_name|
      rl_file = File.join(ext_dir, rl_name)
      c_file = File.join(ext_dir, c_name)

      unless File.exist?(rl_file)
        abort("ERROR: Ragel grammar file not found: #{rl_file}")
      end

      puts "Generating C code from Ragel grammar..."
      puts "  Input: #{rl_file}"
      puts "  Output: #{c_file}"
      puts "  Style: #{ragel_style}"

      ragel_cmd = "ragel #{ragel_flags} #{rl_file} -o #{c_file}"
      unless system(ragel_cmd)
        abort("ERROR: Failed to generate C code from Ragel grammar\nCommand: #{ragel_cmd}")
      end

      unless File.exist?(c_file)
        abort("ERROR: Generated C file not found: #{c_file}")
      end

      puts "Generated #{c_name} successfully"
    end
  end
end
