# frozen_string_literal: true

require "json"
require "time"
require "fileutils"

module Ampberry
  # "Redeploy": re-apply the whole stack from the flake shipped at /opt/ampberry, in the background.
  #   start  → (root, via the control API or CLI) launches a transient systemd unit running `run`
  #   run    → (inside that unit) system-manager switch --flake /opt/ampberry#ampberry, record the
  #            new system path for Clean reboot, then `ampberry provision`; every line of output goes
  #            to /var/log/ampberry/redeploy.log (world-readable) which the web UI streams as its backdrop
  #   status → state file + whether the unit is active
  # One job at a time: the unit name is fixed, so systemd refuses a second start.
  module Redeploy
    UNIT = "ampberry-redeploy"
    SYSTEM_MANAGER_FLAKE = "github:numtide/system-manager/release-26.05"
    # The CLI ships inside the system closure (environment.systemPackages).
    SW_SYSTEM_MANAGER = "/run/system-manager/sw/bin/system-manager"
    # system-manager ≥ 1.1 keeps its profile under system-manager-profiles/; older ones at the root.
    PROFILES = ["/nix/var/nix/profiles/system-manager-profiles/system-manager", "/nix/var/nix/profiles/system-manager"].freeze
    TIMEOUT = 2 * 60 * 60

    class << self
      def log_path = Ampberry.path(:redeploy_log)
      def state_path = Ampberry.path(:redeploy_state)

      def status
        st = File.exist?(state_path) ? (Config.load_json(state_path) rescue { "state" => "unknown" }) : { "state" => "idle" }
        active = Run.try_run("systemctl", "is-active", "#{UNIT}.service", quiet: true, read_only: true).out.strip
        st["unit_active"] = %w[active activating].include?(active)
        st["state"] = "stale" if st["state"] == "running" && !st["unit_active"] && st["pid"] && !alive?(st["pid"])
        st["log"] = log_path
        st["log_size"] = File.exist?(log_path) ? File.size(log_path) : 0
        st
      end

      # Launch the background job. Returns the status hash; raises if one is already running.
      def start(reason: "cli", ampberry_bin: "/run/system-manager/sw/bin/ampberry")
        raise Ampberry::Error, "a redeploy is already running" if status["unit_active"]

        FileUtils.mkdir_p(File.dirname(log_path))
        File.write(log_path, "") unless Run.dry_run
        File.chmod(0o644, log_path) if File.exist?(log_path)
        write_state("state" => "starting", "started_at" => Time.now.utc.iso8601, "reason" => reason)
        Run.run("systemd-run", "--unit", UNIT, "--description", "Ampberry redeploy (flake + provision)",
                "--collect", "--property", "Type=exec", "--same-dir", "--quiet",
                *Ampberry.root.empty? ? [] : ["--setenv", "AMPBERRY_ROOT=#{Ampberry.root}"],
                ampberry_bin, "redeploy", "run", timeout: 30)
        status
      end

      # The job. Returns true on success. Output is appended live to the log file.
      def run(flake: Ampberry.path(:flake), system_manager: nil, provision_cmd: nil)
        FileUtils.mkdir_p(File.dirname(log_path))
        log = File.open(log_path, "a")
        log.sync = true
        File.chmod(0o644, log_path)
        started = Time.now
        write_state("state" => "running", "started_at" => started.utc.iso8601, "pid" => Process.pid, "flake" => flake)
        begin
          say(log, "== ampberry redeploy #{Ampberry::VERSION} - flake #{flake}")
          sm = system_manager || find_system_manager(log)
          stream(log, "#{sm}/bin/system-manager", "switch", "--flake", "#{flake}#ampberry")
          record_system_path(log, sm)
          stream(log, *(provision_cmd || ["/run/system-manager/sw/bin/ampberry", "provision"]))
          say(log, "== redeploy finished in #{(Time.now - started).round}s")
          write_state("state" => "done", "started_at" => started.utc.iso8601, "finished_at" => Time.now.utc.iso8601, "exit" => 0)
          true
        rescue StandardError => e
          say(log, "== redeploy FAILED: #{e.message}")
          write_state("state" => "failed", "started_at" => started.utc.iso8601, "finished_at" => Time.now.utc.iso8601,
                      "exit" => 1, "error" => e.message)
          false
        ensure
          log.close
        end
      end

      private

      def say(log, text)
        line = "#{Time.now.strftime('%H:%M:%S')} #{text}"
        log.puts(line)
        Log.info(text)
      end

      # Spawn with stdout/stderr going straight to the log (live), enforce the overall timeout.
      def stream(log, *cmd)
        say(log, "$ #{Run.shell_quote(cmd)}")
        if Run.runner
          r = Run.runner.call(cmd, {})
          log.print(r[:out].to_s)
          log.print(r[:err].to_s)
          raise Ampberry::Error, "#{cmd.first} exited #{r[:status]}" unless (r[:status] || 0).zero?

          return true
        end
        # child output → the redeploy log file AND our stdout (the journal → the live appliance log)
        reader, writer = IO.pipe
        pid = Process.spawn(*cmd, out: writer, err: writer, in: File::NULL)
        writer.close
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT
        status = nil
        loop do
          ready, = IO.select([reader], nil, nil, 0.5)
          if ready
            begin
              chunk = reader.read_nonblock(65_536)
              log.write(chunk)
              $stdout.write(chunk)
              $stdout.flush
            rescue IO::WaitReadable
              nil
            rescue EOFError
              _, status = Process.wait2(pid)
              break
            end
          end
          unless status
            _, status = Process.wait2(pid, Process::WNOHANG)
            if status
              log.write(reader.read.to_s)
              break
            end
          end
          if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
            Process.kill("TERM", pid)
            sleep 2
            Process.kill("KILL", pid) rescue nil
            Process.wait(pid) rescue nil
            raise Ampberry::Error, "#{cmd.first} timed out after #{TIMEOUT}s"
          end
        end
        reader.close unless reader.closed?
        raise Ampberry::Error, "#{File.basename(cmd.first)} exited #{status.exitstatus || status.inspect}" unless status.success?

        true
      end

      def find_system_manager(log)
        live = File.join(Ampberry.root, SW_SYSTEM_MANAGER)
        return File.realpath(live).delete_suffix("/bin/system-manager") if File.executable?(live)

        recorded = Ampberry.path(:system_manager_path)
        if File.exist?(recorded)
          path = File.read(recorded).strip
          return path if File.executable?("#{path}/bin/system-manager")
        end
        say(log, "fetching system-manager (#{SYSTEM_MANAGER_FLAKE})")
        path = Run.capture("nix", "build", "--no-link", "--print-out-paths", SYSTEM_MANAGER_FLAKE, timeout: 1800, read_only: false).strip
        File.write(recorded, "#{path}\n")
        path
      end

      # Clean reboot activates the recorded closure: keep it pointing at what is live now.
      def record_system_path(log, system_manager)
        File.write(Ampberry.path(:system_manager_path), "#{system_manager}\n")
        profile = PROFILES.map { |p| File.join(Ampberry.root, p) }.find { |p| File.symlink?(p) || File.exist?(p) }
        return unless profile

        target = File.realpath(profile)
        File.write(Ampberry.path(:system_path), "#{target}\n")
        say(log, "system closure: #{target}")
      rescue SystemCallError => e
        say(log, "could not record the system path: #{e.message}")
      end

      def write_state(hash)
        FileUtils.mkdir_p(File.dirname(state_path))
        Config.save_json_atomic(state_path, hash, mode: 0o644)
      end

      def alive?(pid)
        Process.kill(0, Integer(pid))
        true
      rescue StandardError
        false
      end
    end
  end
end
