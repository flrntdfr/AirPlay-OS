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

  def test_start_update_passes_the_release_to_the_job
    with_runner(->(cmd, _o) { cmd.first == "systemctl" ? { status: 3, out: "inactive\n" } : { status: 0 } }) do
      st = R.start(reason: "test", update: { "version" => "5.5.3", "tag" => "5.5.3" })
      run = cmds.find { |c| c.start_with?("systemd-run") }
      assert_match(/ampberry redeploy run --update-shairport 5\.5\.3 5\.5\.3\z/, run)
      assert_equal "update-shairport", st["kind"]
    end
    e = assert_raises(Ampberry::Error) { R.start(update: { "version" => "5.5.3; rm -rf /" }) }
    assert_match(/bad version/, e.message)
  end

  def test_run_update_writes_the_override_flake_locks_it_and_switches_from_it
    src = File.join(ROOT, "nix/store/abc-source") # the flake is the repo root
    FileUtils.mkdir_p(src)
    spit(Ampberry.path(:release), "NAME=\"Ampberry\"\nFLAKE_VERSION=\"647bf3b\"\nBUILD=\"24\"\n")
    sm_dir = File.join(ROOT, "fake-sm-update")
    FileUtils.mkdir_p("#{sm_dir}/bin")
    File.write("#{sm_dir}/bin/system-manager", "#!/bin/sh\necho \"system-manager $*\"\n")
    File.chmod(0o755, "#{sm_dir}/bin/system-manager")
    nix = File.join(ROOT, "fake-nix.sh")
    # nix prints non-ASCII ("unpacking '…' into the Git cache"): must stream through untouched
    File.write(nix, "#!/bin/sh\necho \"nix $*\"\necho \"unpacking 'github:x/y…' into the Git cache...\"\n")
    File.chmod(0o755, nix)
    refresh = File.join(ROOT, "fake-refresh.sh")
    File.write(refresh, "#!/bin/sh\necho refreshed\n")
    File.chmod(0o755, refresh)

    assert R.run(flake: src, system_manager: sm_dir, nix: nix, provision_cmd: [refresh], update: { "version" => "5.5.3", "tag" => "5.5.3" })
    dir = Ampberry.path(:update_flake)
    flake = slurp(File.join(dir, "flake.nix"))
    assert_includes flake, "inputs.ampberry.url = \"path:#{File.realpath(src)}\";", "the shipped flake (its store copy) is the input"
    assert_includes flake, "github:mikebrady/shairport-sync/5.5.3"
    assert_includes flake, 'version = "5.5.3"'
    assert_includes flake, 'device = "ampberry"'
    assert_includes flake, 'build = "24"'
    assert_includes flake, 'flakeVersion = "647bf3b"'
    log = slurp(R.log_path)
    assert_includes log, "nix flake lock #{dir}"
    assert_includes log, "unpacking 'github:x/y…'", "non-ASCII tool output streamed as is"
    assert_includes log, "system-manager switch --flake #{dir}#ampberry"
    assert_match(/== update-shairport finished in \d+s/, log)
    st = JSON.parse(slurp(R.state_path))
    assert_equal %w[done update-shairport], [st["state"], st["kind"]]

    # a flake in a subdirectory of the store copy is referenced with ?dir=
    sub = File.join(src, "os")
    FileUtils.mkdir_p(sub)
    assert R.run(flake: sub, system_manager: sm_dir, nix: nix, provision_cmd: [refresh], update: { "version" => "5.5.3", "tag" => "5.5.3" })
    assert_includes slurp(File.join(dir, "flake.nix")), "path:#{File.realpath(src)}?dir=os"
  end

  def test_action_update_shairport_needs_a_known_newer_release
    ids = Ampberry::Actions.list(path: "/nonexistent").map { |a| a["id"] }
    assert_includes ids, "update-shairport"
    mkdirs("run/ampberry")
    spit(Ampberry.path(:updates), JSON.generate("running" => "5.5.2", "latest" => "5.5.2", "up_to_date" => true))
    r = Ampberry::Actions.run_action("update-shairport")
    refute r["ok"]
    assert_match(/no newer/, r["error"])
    spit(Ampberry.path(:updates), JSON.generate("running" => "5.5.2", "latest" => "5.6.0", "latest_tag" => "5.6.0", "up_to_date" => false))
    with_runner(->(cmd, _o) { cmd.first == "systemctl" ? { status: 3, out: "inactive\n" } : { status: 0 } }) do
      r = Ampberry::Actions.run_action("update-shairport")
      assert r["ok"], r["error"]
      assert_equal "update-shairport", r["result"]["kind"]
      assert_match(/--update-shairport 5\.6\.0 5\.6\.0\z/, cmds.find { |c| c.start_with?("systemd-run") })
    end
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
