# frozen_string_literal: true

# Spinel package entrypoint. spin resolves `require "cataract"` to the file
# named after the package at the package root, so this is that file; all it
# does is hand over to the same lib/cataract.rb every other install loads,
# which picks the pure Ruby backend when RUBY_ENGINE is "spinel".
require_relative 'lib/cataract'
