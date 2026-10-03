# frozen_string_literal: true

# What `require 'webmock/minitest'` loads under `rake test:spinel`.
#
# WebMock cannot be compiled by Spinel, and the Spinel build has no HTTP fetch
# for it to stub in the first place. This keeps a test file that stubs HTTP
# compiling, so its other tests still run; a test that actually stubs a
# request fails where it does so.
module Minitest
  # Answers the calls chained onto stub_request.
  class SpinelWebMockStub
    def with(**_options)
      self
    end

    def to_return(**_options)
      self
    end

    def to_timeout
      self
    end
  end

  class Test
    def stub_request(_method, _uri)
      stub = Minitest::SpinelWebMockStub.new

      flunk 'HTTP cannot be stubbed under Spinel: no WebMock, and no HTTP fetch for it to stub'
      stub
    end
  end
end
