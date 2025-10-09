require 'mkmf'

# Check for ragel
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

unless system("ragel -G2 -C #{rl_file} -o #{c_file}")
  puts "ERROR: Failed to generate C code from Ragel grammar"
  puts "Command: ragel -G2 -C #{rl_file} -o #{c_file}"
  exit 1
end

# Check that the generated file exists
unless File.exist?(c_file)
  puts "ERROR: Generated C file not found: #{c_file}"
  exit 1
end

puts "C parser generated successfully"

# Configure the makefile
create_makefile('cataract/cataract')
