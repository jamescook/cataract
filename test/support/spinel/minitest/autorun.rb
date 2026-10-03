# frozen_string_literal: true

# What `require 'minitest/autorun'` loads under `rake test:spinel`, where this
# directory is ahead of everything else on the load path: the compilable
# subset of Minitest, so a test file that requires Minitest itself does not
# have to change. Nothing "autoruns" - the generated program calls the tests.
require_relative '../../spinel_minitest'
