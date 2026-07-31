# frozen_string_literal: true

require 'fileutils'
require 'json'

# The directory benchmark result JSON is written to and read back from.
#
# A value, passed explicitly, so a test can hand the harness a temp directory
# without touching global state. The environment appears in exactly two
# places - `from_env` reads a location sent by a parent process, `#env`
# produces the entry to send one - because orchestrator and workers are
# separate processes and have to agree on where results go.
class ResultsDirectory
  ENV_VAR = 'CATARACT_BENCH_RESULTS_DIR'
  DEFAULT_PATH = File.expand_path('.results', __dir__)

  # @param env [Hash] environment to read the location from
  def self.from_env(env)
    new(env[ENV_VAR] || DEFAULT_PATH)
  end

  attr_reader :path

  def initialize(path)
    @path = path
    freeze
  end

  def join(filename)
    File.join(path, filename)
  end

  def glob(pattern)
    Dir.glob(File.join(path, pattern))
  end

  def create
    FileUtils.mkdir_p(path)
    self
  end

  def read(filename)
    JSON.parse(File.read(join(filename)))
  end

  def write(filename, data)
    File.write(join(filename), JSON.pretty_generate(data))
  end

  def exist?(filename)
    File.exist?(join(filename))
  end

  def delete(pattern)
    glob(pattern).each { |file| File.delete(file) }
  end

  # Entry handed to a worker subprocess so it writes alongside its parent.
  def env
    { ENV_VAR => path }
  end

  def ==(other)
    other.is_a?(ResultsDirectory) && other.path == path
  end
  alias eql? ==

  def hash
    path.hash
  end

  def to_s
    path
  end
end
