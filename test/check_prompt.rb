#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

Run = Struct.new(:foreground, :background, :text) do
  def to_s
    format("fg=%s bg=%s '%s'", name(foreground), name(background), text)
  end

  private

  def name(colour)
    colour.nil? ? 'None' : colour.to_s
  end
end

class Sequence
  SGR = /\A\e\[([0-9;]*)m/.freeze
  ZSH_WRAPPER = /%[{}]/.freeze

  def self.parse(raw)
    new(raw.gsub(ZSH_WRAPPER, '')).runs
  end

  def initialize(raw)
    @raw = raw
    @foreground = nil
    @background = nil
    @pending = +''
    @runs = []
  end

  def runs
    scan
    flush
    @runs.reject { |run| run.text.empty? }
  end

  private

  def scan
    until @raw.empty?
      match = @raw.match(SGR)
      if match.nil?
        @pending << @raw.slice!(0)
      else
        flush
        apply(match[1])
        @raw = match.post_match
      end
    end
  end

  def apply(codes)
    codes = '0' if codes.empty?
    codes.split(';').each { |code| apply_code(code.to_i) }
  end

  def apply_code(code)
    case code
    when 0 then @foreground = @background = nil
    when 39 then @foreground = nil
    when 49 then @background = nil
    when 30..37 then @foreground = code - 30
    when 40..47 then @background = code - 40
    end
  end

  def flush
    return if @pending.empty?

    @runs << Run.new(@foreground, @background, @pending)
    @pending = +''
  end
end

class Fixture
  BRANCH = 'master'
  OBJECT_FORMAT = 'sha1'
  ABBREV = '7'
  EPOCH = '2000-01-01T00:00:00Z'

  def initialize(state, root)
    @state = state
    @root = root
  end

  def directory
    # non-git exists to show the prompt outside a repository, and /tmp reliably
    # is not one. Nothing is written there, so only this state is non-hermetic.
    repository? ? File.join(@root, 'home', 'code', 'conf') : '/tmp'
  end

  def build
    return self unless repository?

    FileUtils.mkdir_p(directory)
    git 'init', '--initial-branch', BRANCH, '--object-format', OBJECT_FORMAT
    git 'config', 'core.abbrev', ABBREV
    git 'commit', '--no-gpg-sign', '--allow-empty', '--message', 'root'
    dirty! if dirty?
    detach! if detached?
    self
  end

  def sha
    capture('rev-parse', '--short', 'HEAD')
  end

  private

  def repository?
    @state != 'non-git'
  end

  def dirty?
    @state == 'git-dirty'
  end

  def detached?
    @state == 'detached-head'
  end

  def dirty!
    File.write(File.join(directory, 'uncommitted'), "\n")
  end

  def detach!
    git 'checkout', '--detach'
  end

  def git(*arguments)
    system(environment, *command(*arguments),
           out: File::NULL, err: File::NULL) || raise("git #{arguments.first} failed")
  end

  def capture(*arguments)
    output = IO.popen(environment, command(*arguments), err: File::NULL, &:read)
    raise "git #{arguments.first} failed" unless $?.success?

    output.chomp
  end

  def command(*arguments)
    ['git', '-C', directory, *arguments]
  end

  # Identity and timestamps keep the fixture off the machine's git config, which
  # may set neither name nor email and would abort the commit. Pinning the dates
  # too makes the commit sha itself reproducible, so detached-head can pin the
  # rendered value rather than a placeholder standing in for it.
  def environment
    { 'GIT_AUTHOR_NAME' => 'test', 'GIT_AUTHOR_EMAIL' => 'test@example.com',
      'GIT_COMMITTER_NAME' => 'test', 'GIT_COMMITTER_EMAIL' => 'test@example.com',
      'GIT_AUTHOR_DATE' => EPOCH, 'GIT_COMMITTER_DATE' => EPOCH }
  end
end

class Prompt
  CONFIG = File.expand_path('../starship/starship.toml', __dir__)

  class RenderError < StandardError; end

  def initialize(fixture, root)
    @fixture = fixture
    @root = root
  end

  def runs
    Sequence.parse(render)
  end

  private

  def render
    errors = File.join(@root, 'stderr')
    output = IO.popen(environment, command, chdir: @fixture.directory, err: errors, &:read)

    raise RenderError, "starship failed: #{File.read(errors)}" unless $?.success?

    # starship exits 0 on a broken config and reports TOML errors on stderr, so
    # empty stderr is the only evidence the config parsed.
    raise RenderError, "starship wrote to stderr: #{File.read(errors)}" if File.size?(errors)

    output
  end

  def environment
    {
      'STARSHIP_CONFIG' => CONFIG,
      'HOME' => File.join(@root, 'home'),
      'PWD' => @fixture.directory
    }
  end

  def command
    ['starship', 'prompt', '--status=0', '--jobs=0']
  end
end

class Expectation
  DIRECTORY = ENV.fetch('PROMPT_EXPECTED_DIR', File.expand_path('expected-prompts', __dir__))

  def self.exist?(state)
    File.exist?(File.join(DIRECTORY, state))
  end

  def initialize(state)
    @state = state
  end

  def lines
    File.readlines(File.join(DIRECTORY, @state), chomp: true)
        .reject { |line| line.start_with?('#') }
  end
end

class Comparison
  def initialize(state)
    @state = state
  end

  def match?
    actual == expected
  end

  def report
    warn "check-prompt: #{@state} does not match its expectation"
    (expected - actual).each { |line| warn "expected: #{line}" }
    (actual - expected).each { |line| warn "actual:   #{line}" }
  end

  private

  def expected
    @expected ||= Expectation.new(@state).lines
  end

  def actual
    @actual ||= Dir.mktmpdir do |root|
      fixture = Fixture.new(@state, root).build
      Prompt.new(fixture, root).runs.map(&:to_s)
    end
  end
end

def die(message)
  warn "check-prompt: #{message}"
  exit 1
end

state = ARGV.first
die 'usage: check_prompt.rb <state>' if state.nil? || state.empty?
die 'starship is not installed' if `which starship`.empty?
die "unknown state: #{state}" unless Expectation.exist?(state)

comparison = Comparison.new(state)
exit 0 if comparison.match?

comparison.report
exit 1
