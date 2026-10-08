# frozen_string_literal: true

require_relative "test_helper"

class RedeployTest < AmpberryTest
  R = Ampberry::Redeploy

  def setup
    install_defaults
    [R.log_path, R.state_path, Ampberry.path(:system_manager_path), Ampberry.path(:system_path)].each { |f| File.unlink(f) if File.exist?(f) }
  end

  def test_status_idle
    with_runner(->(_c, _o) { { status: 3, out: "inactive\n" } }) do
      st = R.status
      assert_equal "idle", st["state"]
      refute st["unit_active"]
      assert_equal 0, st["log_size"]
    end
  end

  def test_start_launches_a_transient_unit_once
    with_runner(->(cmd, _o) { cmd.first == "systemctl" ? { status: 3, out: "inactive\n" } : { status: 0 } }) do
      st = R.start(reason: "test")
      run = cmds.find { |c| c.start_with?("systemd-run") }
      assert run, "systemd-run invoked"
      assert_includes run, "--unit ampberry-redeploy"
      assert_includes run, "--collect"
      assert_match(%r{/run/system-manager/sw/bin/ampberry redeploy run\z}, run)
      assert_equal "starting", st["state"]
      assert File.exist?(R.log_path)
      assert_equal "644", format("%o", File.stat(R.log_path).mode & 0o777), "log is world-readable for the UI"
    end
    with_runner(->(cmd, _o) { cmd.first == "systemctl" ? { status: 0, out: "active\n" } : { status: 0 } }) do
      e = assert_raises(Ampberry::Error) { R.start }
      assert_match(/already running/, e.message)
      refute cmds.any? { |c| c.start_with?("systemd-run") }
    end
  end

  def test_run_streams_both_steps_and_records_state
    sm_dir = File.join(ROOT, "fake-sm")
    FileUtils.mkdir_p("#{sm_dir}/bin")
    File.write("#{sm_dir}/bin/system-manager", "#!/bin/sh\necho \"system-manager $*\"\necho 'activating...' >&2\n")
    File.chmod(0o755, "#{sm_dir}/bin/system-manager")
    prov = File.join(ROOT, "fake-provision.sh")
    File.write(prov, "#!/bin/sh\necho provision-ok\n")
    File.chmod(0o755, prov)

    assert R.run(flake: "/opt/ampberry", system_manager: sm_dir, provision_cmd: [prov])
    log = slurp(R.log_path)
    assert_match(/\$ #{Regexp.escape(sm_dir)}\/bin\/system-manager switch --flake \/opt\/ampberry\\?#ampberry/, log)
    assert_includes log, "system-manager switch --flake /opt/ampberry#ampberry"
    assert_includes log, "activating...", "stderr streamed too"
    assert_includes log, "provision-ok"
    assert_match(/== redeploy finished in \d+s/, log)
    st = JSON.parse(slurp(R.state_path))
    assert_equal "done", st["state"]
    assert_equal 0, st["exit"]
    assert_equal "#{sm_dir}\n", slurp(Ampberry.path(:system_manager_path))
  end

  def test_run_failure_is_recorded
    sm_dir = File.join(ROOT, "fake-sm-fail")
    FileUtils.mkdir_p("#{sm_dir}/bin")
    File.write("#{sm_dir}/bin/system-manager", "#!/bin/sh\necho 'error: evaluation failed' >&2\nexit 1\n")
    File.chmod(0o755, "#{sm_dir}/bin/system-manager")
    refute R.run(flake: "/opt/ampberry", system_manager: sm_dir, provision_cmd: ["/bin/true"])
    log = slurp(R.log_path)
    assert_includes log, "evaluation failed"
    assert_match(/== redeploy FAILED: system-manager exited 1/, log)
    refute_includes log, "provision", "provision must not run after a failed switch"
    assert_equal "failed", JSON.parse(slurp(R.state_path))["state"]
  end

  def test_action_redeploy_is_exposed
    ids = Ampberry::Actions.list(path: "/nonexistent").map { |a| a["id"] }
    assert_includes ids, "redeploy"
    with_runner(->(cmd, _o) { cmd.first == "systemctl" ? { status: 3, out: "inactive\n" } : { status: 0 } }) do
      r = Ampberry::Actions.run_action("redeploy")
      assert r["ok"], r["error"]
      assert_equal "starting", r["result"]["state"]
    end
  end
end
