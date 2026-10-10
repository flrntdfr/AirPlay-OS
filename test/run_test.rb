# frozen_string_literal: true

require_relative "test_helper"

class RunTest < AirPlayOSTest
  R = AirPlayOS::Run
  RUBY = RbConfig.ruby

  def test_real_execution_captures_both_streams
    r = R.run(RUBY, "-e", "print 'out'; $stderr.print 'err'", quiet: true)
    assert_equal 0, r.status
    assert_equal "out", r.out
    assert_equal "err", r.err
  end

  def test_capture_chomps
    assert_equal "line", R.capture(RUBY, "-e", "puts 'line'", quiet: true)
    assert_equal "x\n", R.capture(RUBY, "-e", "puts 'x'", chomp: false, quiet: true)
  end

  def test_stdin_and_env
    assert_equal "HELLO\n", R.run(RUBY, "-ne", "print $_.upcase", stdin: "hello\n", quiet: true).out
    assert_equal "v", R.run(RUBY, "-e", "print ENV['AIRPLAY_OS_T']", env: { "AIRPLAY_OS_T" => "v" }, quiet: true).out
    refute ENV.key?("AIRPLAY_OS_T")
  end

  def test_failure_handling
    assert_equal 3, R.try_run(RUBY, "-e", "exit 3", quiet: true).status
    e = assert_raises(R::CommandError) { R.run(RUBY, "-e", "$stderr.puts 'boom'; exit 3", quiet: true) }
    assert_match(/exit 3/, e.message)
    assert_match(/boom/, e.message)
    assert_equal 3, R.run(RUBY, "-e", "exit 3", ok: [0, 3], quiet: true).status
  end

  def test_timeout_kills_child
    t = Time.now
    r = R.try_run(RUBY, "-e", "sleep 10", timeout: 1, quiet: true)
    assert_equal 124, r.status
    assert_match(/timed out/, r.err)
    assert_operator Time.now - t, :<, 8
  end

  def test_missing_binary
    e = assert_raises(R::CommandError) { R.run("/nonexistent/binary/airplay-os-x", quiet: true) }
    assert_match(/cannot execute/, e.message)
  end

  def test_large_output_does_not_deadlock
    r = R.run(RUBY, "-e", "print 'x' * 300_000; $stderr.print 'y' * 300_000", quiet: true)
    assert_equal 300_000, r.out.bytesize
    assert_equal 300_000, r.err.bytesize
  end

  def test_mock_runner_and_dry_run
    seen = []
    R.runner = ->(cmd, _opts) { seen << cmd; { status: 0, out: "mock\n" } }
    assert_equal "mock", R.capture("nmcli", "device", quiet: true)
    assert_equal [%w[nmcli device]], seen
  ensure
    R.runner = nil
  end

  def test_dry_run
    R.dry_run = true
    r = R.try_run(RUBY, "-e", "exit 9", quiet: true)
    assert_equal 0, r.status
    assert r.dry_run
    assert_equal "real", R.capture(RUBY, "-e", "print 'real'", quiet: true), "read_only commands still run"
  ensure
    R.dry_run = false
  end

  def test_shell_quote_for_display
    assert_equal "a b\\ c it\\'s", R.shell_quote(["a", "b c", "it's"])
  end
end
