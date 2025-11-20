# frozen_string_literal: true

module Cataract
  # Default URI resolver proc for converting relative URLs to absolute
  # Uses Ruby's URI stdlib to merge base and relative URIs
  DEFAULT_URI_RESOLVER = lambda { |base, relative|
    require 'uri'
    URI.parse(base).merge(relative).to_s
  }.freeze
end
