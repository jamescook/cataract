
# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 1 "lib/cataract/pure_ruby_parser.rb"

# line 50 "lib/cataract/pure_ruby_parser.rb"


module Cataract
  class PureRubyParser
    def initialize
      @rules = []
      @current_rule = {}
      @mark_start = 0
      @current_property_start = 0
      @current_property_end = 0
      @current_value_start = 0
      @current_value_end = 0
      
# line 19 "lib/cataract/pure_ruby_parser.rb.tmp"
class << self
	attr_accessor :_simple_css_actions
	private :_simple_css_actions, :_simple_css_actions=
end
self._simple_css_actions = [
	0, 1, 0, 1, 1, 1, 2, 1, 
	3, 1, 4, 1, 7, 2, 5, 6, 
	2, 7, 0
]

class << self
	attr_accessor :_simple_css_key_offsets
	private :_simple_css_key_offsets, :_simple_css_key_offsets=
end
self._simple_css_key_offsets = [
	0, 0, 4, 16, 21, 29, 41, 46, 
	58, 59, 64, 69, 70, 71, 73, 78, 
	91, 97, 106, 119, 125, 138, 140, 146, 
	152, 155, 161, 175, 182, 192, 206, 213, 
	226, 233, 240, 243, 250, 252, 255, 261, 
	275, 282, 292, 306, 313, 326, 335, 342, 
	356, 360, 367, 382, 390, 401, 416, 424, 
	437, 445, 453, 463, 478, 487, 501, 509, 
	522, 523, 530, 542, 553, 564, 575, 587, 
	599, 612, 624, 637, 650
]

class << self
	attr_accessor :_simple_css_trans_keys
	private :_simple_css_trans_keys, :_simple_css_trans_keys=
end
self._simple_css_trans_keys = [
	65, 90, 97, 122, 13, 32, 45, 123, 
	9, 10, 48, 57, 65, 90, 97, 122, 
	13, 32, 123, 9, 10, 13, 32, 9, 
	10, 65, 90, 97, 122, 13, 32, 45, 
	58, 9, 10, 48, 57, 65, 90, 97, 
	122, 13, 32, 58, 9, 10, 13, 32, 
	34, 39, 9, 10, 48, 57, 65, 90, 
	97, 122, 34, 13, 32, 125, 9, 10, 
	13, 32, 125, 9, 10, 42, 42, 42, 
	47, 42, 65, 90, 97, 122, 13, 32, 
	42, 45, 123, 9, 10, 48, 57, 65, 
	90, 97, 122, 13, 32, 42, 123, 9, 
	10, 13, 32, 42, 9, 10, 65, 90, 
	97, 122, 13, 32, 42, 45, 58, 9, 
	10, 48, 57, 65, 90, 97, 122, 13, 
	32, 42, 58, 9, 10, 13, 32, 34, 
	39, 42, 9, 10, 48, 57, 65, 90, 
	97, 122, 34, 42, 13, 32, 42, 125, 
	9, 10, 13, 32, 42, 125, 9, 10, 
	34, 42, 47, 34, 42, 65, 90, 97, 
	122, 13, 32, 34, 42, 45, 123, 9, 
	10, 48, 57, 65, 90, 97, 122, 13, 
	32, 34, 42, 123, 9, 10, 13, 32, 
	34, 42, 9, 10, 65, 90, 97, 122, 
	13, 32, 34, 42, 45, 58, 9, 10, 
	48, 57, 65, 90, 97, 122, 13, 32, 
	34, 42, 58, 9, 10, 13, 32, 34, 
	39, 42, 9, 10, 48, 57, 65, 90, 
	97, 122, 13, 32, 34, 42, 125, 9, 
	10, 13, 32, 34, 42, 125, 9, 10, 
	34, 39, 42, 13, 32, 39, 42, 125, 
	9, 10, 39, 42, 39, 42, 47, 39, 
	42, 65, 90, 97, 122, 13, 32, 39, 
	42, 45, 123, 9, 10, 48, 57, 65, 
	90, 97, 122, 13, 32, 39, 42, 123, 
	9, 10, 13, 32, 39, 42, 9, 10, 
	65, 90, 97, 122, 13, 32, 39, 42, 
	45, 58, 9, 10, 48, 57, 65, 90, 
	97, 122, 13, 32, 39, 42, 58, 9, 
	10, 13, 32, 34, 39, 42, 9, 10, 
	48, 57, 65, 90, 97, 122, 13, 32, 
	39, 42, 125, 9, 10, 48, 57, 13, 
	32, 39, 42, 125, 9, 10, 13, 32, 
	39, 42, 45, 125, 9, 10, 48, 57, 
	65, 90, 97, 122, 34, 39, 42, 47, 
	34, 39, 42, 65, 90, 97, 122, 13, 
	32, 34, 39, 42, 45, 123, 9, 10, 
	48, 57, 65, 90, 97, 122, 13, 32, 
	34, 39, 42, 123, 9, 10, 13, 32, 
	34, 39, 42, 9, 10, 65, 90, 97, 
	122, 13, 32, 34, 39, 42, 45, 58, 
	9, 10, 48, 57, 65, 90, 97, 122, 
	13, 32, 34, 39, 42, 58, 9, 10, 
	13, 32, 34, 39, 42, 9, 10, 48, 
	57, 65, 90, 97, 122, 13, 32, 34, 
	39, 42, 125, 9, 10, 13, 32, 34, 
	39, 42, 125, 9, 10, 13, 32, 34, 
	39, 42, 125, 9, 10, 48, 57, 13, 
	32, 34, 39, 42, 45, 125, 9, 10, 
	48, 57, 65, 90, 97, 122, 13, 32, 
	34, 42, 125, 9, 10, 48, 57, 13, 
	32, 34, 42, 45, 125, 9, 10, 48, 
	57, 65, 90, 97, 122, 13, 32, 42, 
	125, 9, 10, 48, 57, 13, 32, 42, 
	45, 125, 9, 10, 48, 57, 65, 90, 
	97, 122, 39, 13, 32, 125, 9, 10, 
	48, 57, 13, 32, 45, 125, 9, 10, 
	48, 57, 65, 90, 97, 122, 13, 32, 
	35, 46, 47, 9, 10, 65, 90, 97, 
	122, 13, 32, 35, 46, 47, 9, 10, 
	65, 90, 97, 122, 13, 32, 35, 42, 
	46, 9, 10, 65, 90, 97, 122, 13, 
	32, 35, 42, 46, 47, 9, 10, 65, 
	90, 97, 122, 13, 32, 34, 35, 42, 
	46, 9, 10, 65, 90, 97, 122, 13, 
	32, 34, 35, 42, 46, 47, 9, 10, 
	65, 90, 97, 122, 13, 32, 35, 39, 
	42, 46, 9, 10, 65, 90, 97, 122, 
	13, 32, 35, 39, 42, 46, 47, 9, 
	10, 65, 90, 97, 122, 13, 32, 34, 
	35, 39, 42, 46, 9, 10, 65, 90, 
	97, 122, 13, 32, 34, 35, 39, 42, 
	46, 47, 9, 10, 65, 90, 97, 122, 
	0
]

class << self
	attr_accessor :_simple_css_single_lengths
	private :_simple_css_single_lengths, :_simple_css_single_lengths=
end
self._simple_css_single_lengths = [
	0, 0, 4, 3, 2, 4, 3, 4, 
	1, 3, 3, 1, 1, 2, 1, 5, 
	4, 3, 5, 4, 5, 2, 4, 4, 
	3, 2, 6, 5, 4, 6, 5, 5, 
	5, 5, 3, 5, 2, 3, 2, 6, 
	5, 4, 6, 5, 5, 5, 5, 6, 
	4, 3, 7, 6, 5, 7, 6, 5, 
	6, 6, 6, 7, 5, 6, 4, 5, 
	1, 3, 4, 5, 5, 5, 6, 6, 
	7, 6, 7, 7, 8
]

class << self
	attr_accessor :_simple_css_range_lengths
	private :_simple_css_range_lengths, :_simple_css_range_lengths=
end
self._simple_css_range_lengths = [
	0, 2, 4, 1, 3, 4, 1, 4, 
	0, 1, 1, 0, 0, 0, 2, 4, 
	1, 3, 4, 1, 4, 0, 1, 1, 
	0, 2, 4, 1, 3, 4, 1, 4, 
	1, 1, 0, 1, 0, 0, 2, 4, 
	1, 3, 4, 1, 4, 2, 1, 4, 
	0, 2, 4, 1, 3, 4, 1, 4, 
	1, 1, 2, 4, 2, 4, 2, 4, 
	0, 2, 4, 3, 3, 3, 3, 3, 
	3, 3, 3, 3, 3
]

class << self
	attr_accessor :_simple_css_index_offsets
	private :_simple_css_index_offsets, :_simple_css_index_offsets=
end
self._simple_css_index_offsets = [
	0, 0, 3, 12, 17, 23, 32, 37, 
	46, 48, 53, 58, 60, 62, 65, 69, 
	79, 85, 92, 102, 108, 118, 121, 127, 
	133, 137, 142, 153, 160, 168, 179, 186, 
	196, 203, 210, 214, 221, 224, 228, 233, 
	244, 251, 259, 270, 277, 287, 295, 302, 
	313, 318, 324, 336, 344, 353, 365, 373, 
	383, 391, 399, 408, 420, 428, 439, 446, 
	456, 458, 464, 473, 482, 491, 500, 510, 
	520, 531, 541, 552, 563
]

class << self
	attr_accessor :_simple_css_trans_targs
	private :_simple_css_trans_targs, :_simple_css_trans_targs=
end
self._simple_css_trans_targs = [
	2, 2, 0, 3, 3, 2, 4, 3, 
	2, 2, 2, 0, 3, 3, 4, 3, 
	0, 4, 4, 4, 5, 5, 0, 6, 
	6, 5, 7, 6, 5, 5, 5, 0, 
	6, 6, 7, 6, 0, 7, 7, 8, 
	64, 7, 65, 66, 66, 0, 9, 8, 
	10, 10, 68, 10, 0, 10, 10, 68, 
	10, 0, 12, 0, 13, 12, 13, 69, 
	12, 13, 15, 15, 12, 16, 16, 13, 
	15, 17, 16, 15, 15, 15, 12, 16, 
	16, 13, 17, 16, 12, 17, 17, 13, 
	17, 18, 18, 12, 19, 19, 13, 18, 
	20, 19, 18, 18, 18, 12, 19, 19, 
	13, 20, 19, 12, 20, 20, 21, 36, 
	13, 20, 62, 63, 63, 12, 22, 24, 
	21, 23, 23, 13, 70, 23, 12, 23, 
	23, 13, 70, 23, 12, 22, 24, 71, 
	21, 22, 24, 26, 26, 21, 27, 27, 
	22, 24, 26, 28, 27, 26, 26, 26, 
	21, 27, 27, 22, 24, 28, 27, 21, 
	28, 28, 22, 24, 28, 29, 29, 21, 
	30, 30, 22, 24, 29, 31, 30, 29, 
	29, 29, 21, 30, 30, 22, 24, 31, 
	30, 21, 31, 31, 32, 34, 24, 31, 
	60, 61, 61, 21, 33, 33, 22, 24, 
	72, 33, 21, 33, 33, 22, 24, 72, 
	33, 21, 35, 32, 48, 34, 46, 46, 
	22, 37, 74, 46, 36, 22, 37, 36, 
	22, 37, 73, 36, 22, 37, 39, 39, 
	36, 40, 40, 22, 37, 39, 41, 40, 
	39, 39, 39, 36, 40, 40, 22, 37, 
	41, 40, 36, 41, 41, 22, 37, 41, 
	42, 42, 36, 43, 43, 22, 37, 42, 
	44, 43, 42, 42, 42, 36, 43, 43, 
	22, 37, 44, 43, 36, 44, 44, 34, 
	35, 37, 44, 45, 47, 47, 36, 46, 
	46, 22, 37, 74, 46, 45, 36, 46, 
	46, 22, 37, 74, 46, 36, 46, 46, 
	22, 37, 47, 74, 46, 47, 47, 47, 
	36, 35, 32, 48, 75, 34, 35, 32, 
	48, 50, 50, 34, 51, 51, 35, 32, 
	48, 50, 52, 51, 50, 50, 50, 34, 
	51, 51, 35, 32, 48, 52, 51, 34, 
	52, 52, 35, 32, 48, 52, 53, 53, 
	34, 54, 54, 35, 32, 48, 53, 55, 
	54, 53, 53, 53, 34, 54, 54, 35, 
	32, 48, 55, 54, 34, 55, 55, 56, 
	56, 48, 55, 58, 59, 59, 34, 57, 
	57, 35, 32, 48, 76, 57, 34, 57, 
	57, 35, 32, 48, 76, 57, 34, 57, 
	57, 35, 32, 48, 76, 57, 58, 34, 
	57, 57, 35, 32, 48, 59, 76, 57, 
	59, 59, 59, 34, 33, 33, 22, 24, 
	72, 33, 60, 21, 33, 33, 22, 24, 
	61, 72, 33, 61, 61, 61, 21, 23, 
	23, 13, 70, 23, 62, 12, 23, 23, 
	13, 63, 70, 23, 63, 63, 63, 12, 
	9, 64, 10, 10, 68, 10, 65, 0, 
	10, 10, 66, 68, 10, 66, 66, 66, 
	0, 67, 67, 1, 1, 11, 67, 2, 
	2, 0, 67, 67, 1, 1, 11, 67, 
	2, 2, 0, 69, 69, 14, 13, 14, 
	69, 15, 15, 12, 69, 69, 14, 13, 
	14, 12, 69, 15, 15, 12, 71, 71, 
	22, 25, 24, 25, 71, 26, 26, 21, 
	71, 71, 22, 25, 24, 25, 21, 71, 
	26, 26, 21, 73, 73, 38, 22, 37, 
	38, 73, 39, 39, 36, 73, 73, 38, 
	22, 37, 38, 36, 73, 39, 39, 36, 
	75, 75, 35, 49, 32, 48, 49, 75, 
	50, 50, 34, 75, 75, 35, 49, 32, 
	48, 49, 34, 75, 50, 50, 34, 0
]

class << self
	attr_accessor :_simple_css_trans_actions
	private :_simple_css_trans_actions, :_simple_css_trans_actions=
end
self._simple_css_trans_actions = [
	1, 1, 0, 3, 3, 0, 3, 3, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 5, 5, 0, 7, 
	7, 0, 7, 7, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 9, 
	9, 0, 9, 9, 9, 0, 0, 0, 
	13, 13, 13, 13, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 1, 1, 0, 3, 3, 0, 
	0, 3, 3, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 5, 5, 0, 7, 7, 0, 0, 
	7, 7, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 9, 9, 
	0, 0, 9, 9, 9, 0, 0, 0, 
	0, 13, 13, 0, 13, 13, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 1, 1, 0, 3, 3, 
	0, 0, 0, 3, 3, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 5, 5, 0, 
	7, 7, 0, 0, 0, 7, 7, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 9, 9, 0, 0, 
	9, 9, 9, 0, 13, 13, 0, 0, 
	13, 13, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 13, 13, 
	0, 0, 13, 13, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 1, 1, 
	0, 3, 3, 0, 0, 0, 3, 3, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	5, 5, 0, 7, 7, 0, 0, 0, 
	7, 7, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 9, 
	9, 0, 0, 9, 9, 9, 0, 13, 
	13, 0, 0, 13, 13, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 13, 13, 
	0, 0, 0, 13, 13, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 1, 1, 0, 3, 3, 0, 0, 
	0, 0, 3, 3, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 5, 5, 
	0, 7, 7, 0, 0, 0, 0, 7, 
	7, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 9, 
	9, 0, 0, 9, 9, 9, 0, 13, 
	13, 0, 0, 0, 13, 13, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 13, 
	13, 0, 0, 0, 13, 13, 0, 0, 
	13, 13, 0, 0, 0, 0, 13, 13, 
	0, 0, 0, 0, 13, 13, 0, 0, 
	13, 13, 0, 0, 13, 13, 0, 0, 
	0, 13, 13, 0, 0, 0, 0, 13, 
	13, 0, 13, 13, 0, 0, 13, 13, 
	0, 0, 13, 13, 0, 0, 0, 0, 
	0, 0, 13, 13, 13, 13, 0, 0, 
	13, 13, 0, 13, 13, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 1, 
	1, 0, 11, 11, 11, 11, 11, 11, 
	16, 16, 0, 0, 0, 0, 0, 0, 
	0, 1, 1, 0, 11, 11, 11, 0, 
	11, 11, 11, 16, 16, 0, 0, 0, 
	0, 0, 0, 0, 0, 1, 1, 0, 
	11, 11, 0, 11, 0, 11, 11, 11, 
	16, 16, 0, 0, 0, 0, 0, 0, 
	0, 0, 1, 1, 0, 11, 11, 11, 
	0, 0, 11, 11, 11, 16, 16, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	1, 1, 0, 11, 11, 0, 11, 0, 
	0, 11, 11, 11, 16, 16, 0, 0
]

class << self
	attr_accessor :_simple_css_eof_actions
	private :_simple_css_eof_actions, :_simple_css_eof_actions=
end
self._simple_css_eof_actions = [
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 0, 0, 0, 0, 
	0, 0, 0, 0, 11, 0, 11, 0, 
	11, 0, 11, 0, 11
]

class << self
	attr_accessor :simple_css_start
end
self.simple_css_start = 67;
class << self
	attr_accessor :simple_css_first_final
end
self.simple_css_first_final = 67;
class << self
	attr_accessor :simple_css_error
end
self.simple_css_error = 0;

class << self
	attr_accessor :simple_css_en_main
end
self.simple_css_en_main = 67;


# line 62 "lib/cataract/pure_ruby_parser.rb"

    end
    
    def parse(css_string)
      data = css_string
      @data = data
      @rules.clear
      p = 0
      pe = data.length
      eof = pe
      
      
# line 396 "lib/cataract/pure_ruby_parser.rb.tmp"
begin
	p ||= 0
	pe ||= data.length
	cs = simple_css_start
end

# line 73 "lib/cataract/pure_ruby_parser.rb"

      
# line 406 "lib/cataract/pure_ruby_parser.rb.tmp"
begin
	_klen, _trans, _keys, _acts, _nacts = nil
	_goto_level = 0
	_resume = 10
	_eof_trans = 15
	_again = 20
	_test_eof = 30
	_out = 40
	while true
	_trigger_goto = false
	if _goto_level <= 0
	if p == pe
		_goto_level = _test_eof
		next
	end
	if cs == 0
		_goto_level = _out
		next
	end
	end
	if _goto_level <= _resume
	_keys = _simple_css_key_offsets[cs]
	_trans = _simple_css_index_offsets[cs]
	_klen = _simple_css_single_lengths[cs]
	_break_match = false
	
	begin
	  if _klen > 0
	     _lower = _keys
	     _upper = _keys + _klen - 1

	     loop do
	        break if _upper < _lower
	        _mid = _lower + ( (_upper - _lower) >> 1 )

	        if data[p].ord < _simple_css_trans_keys[_mid]
	           _upper = _mid - 1
	        elsif data[p].ord > _simple_css_trans_keys[_mid]
	           _lower = _mid + 1
	        else
	           _trans += (_mid - _keys)
	           _break_match = true
	           break
	        end
	     end # loop
	     break if _break_match
	     _keys += _klen
	     _trans += _klen
	  end
	  _klen = _simple_css_range_lengths[cs]
	  if _klen > 0
	     _lower = _keys
	     _upper = _keys + (_klen << 1) - 2
	     loop do
	        break if _upper < _lower
	        _mid = _lower + (((_upper-_lower) >> 1) & ~1)
	        if data[p].ord < _simple_css_trans_keys[_mid]
	          _upper = _mid - 2
	        elsif data[p].ord > _simple_css_trans_keys[_mid+1]
	          _lower = _mid + 2
	        else
	          _trans += ((_mid - _keys) >> 1)
	          _break_match = true
	          break
	        end
	     end # loop
	     break if _break_match
	     _trans += _klen
	  end
	end while false
	cs = _simple_css_trans_targs[_trans]
	if _simple_css_trans_actions[_trans] != 0
		_acts = _simple_css_trans_actions[_trans]
		_nacts = _simple_css_actions[_acts]
		_acts += 1
		while _nacts > 0
			_nacts -= 1
			_acts += 1
			case _simple_css_actions[_acts - 1]
when 0 then
# line 5 "lib/cataract/pure_ruby_parser.rb"
		begin
 mark_start 		end
when 1 then
# line 6 "lib/cataract/pure_ruby_parser.rb"
		begin
 capture_selector 		end
when 2 then
# line 7 "lib/cataract/pure_ruby_parser.rb"
		begin
 mark_start 		end
when 3 then
# line 8 "lib/cataract/pure_ruby_parser.rb"
		begin
 capture_property 		end
when 4 then
# line 9 "lib/cataract/pure_ruby_parser.rb"
		begin
 mark_start 		end
when 5 then
# line 10 "lib/cataract/pure_ruby_parser.rb"
		begin
 capture_value 		end
when 6 then
# line 11 "lib/cataract/pure_ruby_parser.rb"
		begin
 finish_declaration 		end
when 7 then
# line 12 "lib/cataract/pure_ruby_parser.rb"
		begin
 finish_rule 		end
# line 518 "lib/cataract/pure_ruby_parser.rb.tmp"
			end # action switch
		end
	end
	if _trigger_goto
		next
	end
	end
	if _goto_level <= _again
	if cs == 0
		_goto_level = _out
		next
	end
	p += 1
	if p != pe
		_goto_level = _resume
		next
	end
	end
	if _goto_level <= _test_eof
	if p == eof
	__acts = _simple_css_eof_actions[cs]
	__nacts =  _simple_css_actions[__acts]
	__acts += 1
	while __nacts > 0
		__nacts -= 1
		__acts += 1
		case _simple_css_actions[__acts - 1]
when 7 then
# line 12 "lib/cataract/pure_ruby_parser.rb"
		begin
 finish_rule 		end
# line 550 "lib/cataract/pure_ruby_parser.rb.tmp"
		end # eof action switch
	end
	if _trigger_goto
		next
	end
end
	end
	if _goto_level <= _out
		break
	end
	end
	end

# line 74 "lib/cataract/pure_ruby_parser.rb"

      
      if cs >= simple_css_first_final
        @rules
      else
        raise "Parse failed at position #{p}: '#{data[p, 10]}...'"
      end
    end
    
    private
    
    # Optimized action methods
    def mark_start
      @mark_start = p
    end
    
    def capture_selector
      @current_rule = {
        selector: @data[@mark_start...p],
        declarations: {}
      }
    end
    
    def capture_property  
      @current_property_start = @mark_start
      @current_property_end = p
    end
    
    def capture_value
      @current_value_start = @mark_start  
      @current_value_end = p
    end
    
    def finish_declaration
      prop = @data[@current_property_start...@current_property_end]
      val = @data[@current_value_start...@current_value_end]
      @current_rule[:declarations][prop] = val
    end
    
    def finish_rule
      @rules << @current_rule
      @current_rule = {}
    end
  end
end
