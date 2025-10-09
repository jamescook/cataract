require 'mkmf'

ragel_version = `ragel --version 2>/dev/null`
if $?.success?
  puts "Found Ragel: #{ragel_version.strip}"
else
  puts "ERROR: Ragel not found. Please install ragel:"
  puts "  macOS: brew install ragel"
  puts "  Ubuntu: sudo apt-get install ragel"
  puts "  Or download from: http://www.colm.net/open-source/ragel/"
  exit 1
end

# Get the correct path to the .rl file
ext_dir = File.dirname(__FILE__)
rl_file = File.join(ext_dir, "cataract.rl")
c_file = File.join(ext_dir, "cataract.c")

unless File.exist?(rl_file)
  puts "ERROR: Ragel grammar file not found: #{rl_file}"
  exit 1
end

# Generate C code from Ragel grammar
puts "Generating C parser from Ragel grammar..."
puts "  Input: #{rl_file}"
puts "  Output: #{c_file}"

# Use -G2 (goto-driven, faster) for gem builds, skip for development
# Development: Fast compilation for iteration
# Production: -G2 generates faster code
ragel_flags = if ENV['CATARACT_DEV_BUILD']
  puts "  Mode: Development (fast compilation)"
  "-C"
else
  puts "  Mode: Production (optimized -G2)"
  "-G2 -C"
end

ragel_cmd = "ragel #{ragel_flags} #{rl_file} -o #{c_file}"
unless system(ragel_cmd)
  puts "ERROR: Failed to generate C code from Ragel grammar"
  puts "Command: #{ragel_cmd}"
  exit 1
end

unless File.exist?(c_file)
  puts "ERROR: Generated C file not found: #{c_file}"
  exit 1
end

puts "C parser generated successfully"

create_makefile('cataract/cataract')
