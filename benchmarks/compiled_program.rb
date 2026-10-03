# frozen_string_literal: true

# A benchmark's workload written as a standalone Ruby program, for a backend
# that is compiled ahead of time rather than loaded into a Ruby process.
#
# The ordinary workers measure with benchmark-ips inside the harness; neither
# can be compiled, so such a backend gets the same test cases as a program of
# its own (benchmarks/spinel/) plus the arguments that tell it where its
# inputs are.
#
# @!attribute source [String] the program's entry file
# @!attribute args [Array<String>] arguments the built executable is run with
CompiledProgram = Data.define(:source, :args)
