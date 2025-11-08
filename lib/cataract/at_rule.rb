# frozen_string_literal: true

module Cataract
  # Extension methods for AtRule struct
  # AtRule is defined in C as: Struct.new(:id, :selector, :content, :specificity)
  # - For @keyframes: content is Array of Rule (keyframe blocks)
  # - For @font-face: content is Array of Declaration
  class AtRule
    # AtRule does not support each_selector iteration (it's a definition, not a selector)
    # @return [Boolean] false
    def supports_each_selector?
      false
    end
  end
end
