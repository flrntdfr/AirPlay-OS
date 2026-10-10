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
  #
  # The same job in "update" mode (`update: { "version", "tag" }`, the UI's Update button) puts a
  # newer shairport-sync release on top of the shipped flake: it writes a tiny flake under
  # /var/lib/ampberry/shairport-update that takes /opt/ampberry as an input and calls its
  # lib.withShairport with the release tarball, locks it, switches from it, then refreshes the
  # update cache (ampberry-updates.service) so the UI sees the new running version. A later
  # Redeploy (from /opt/ampberry) returns to the pinned version; the permanent fix is a flake bump.
  module Redeploy
    UNIT = "ampberry-redeploy"
    SYSTEM_MANAGER_FLAKE = "github:numtide/system-manager/release-26.05"
    # The CLI ships inside the system closure (environment.systemPackages).
    SW_SYSTEM_MANAGER = "/run/system-manager/sw/bin/system-manager"
    # system-manager ≥ 1.1 keeps its profile under system-manager-profiles/; older ones at the root.
    PROFILES = ["/nix/var/nix/profiles/system-manager-profiles/system-manager", "/nix/var/nix/profiles/system-manager"].freeze
    NIX = "/nix/var/nix/profiles/default/bin/nix"
    UPSTREAM = "mikebrady/shairport-sync"
    RELEASE_RE = /\A[0-9A-Za-z][0-9A-Za-z._-]{0,40}\z/ # what may go into the generated flake
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
      def start(reason: "cli", ampberry_bin: "/run/system-manager/sw/bin/ampberry", update: nil)
        update = check_update(update) if update
        raise Ampberry::Error, "a redeploy is already running" if status["unit_active"]

        FileUtils.mkdir_p(File.dirname(log_path))
        File.write(log_path, "") unless Run.dry_run
        File.chmod(0o644, log_path) if File.exist?(log_path)
        write_state("state" => "starting", "kind" => kind_of(update), "started_at" => Time.now.utc.iso8601, "reason" => reason)
        Run.run("systemd-run", "--unit", UNIT,
                "--description", (update ? "Ampberry shairport-sync update (#{update['version']})" : "Ampberry redeploy (flake + provision)"),
                "--collect", "--property", "Type=exec", "--same-dir", "--quiet",
                *Ampberry.root.empty? ? [] : ["--setenv", "AMPBERRY_ROOT=#{Ampberry.root}"],
                ampberry_bin, "redeploy", "run", *(update ? ["--update-shairport", update["version"], update["tag"]] : []),
                timeout: 30)
        status
      end

      # The job. Returns true on success. Output is appended live to the log file.
      def run(flake: Ampberry.path(:flake), system_manager: nil, provision_cmd: nil, update: nil, nix: nil)
        update = check_update(update) if update
        kind = kind_of(update)
        FileUtils.mkdir_p(File.dirname(log_path))
        log = File.open(log_path, "a")
        log.sync = true
        File.chmod(0o644, log_path)
        started = Time.now
        write_state("state" => "running", "kind" => kind, "started_at" => started.utc.iso8601, "pid" => Process.pid, "flake" => flake)
        begin
          attr = Ampberry.device["id"] # systemConfigs.<id> of the flake
          if update
            say(log, "== ampberry shairport-sync update → #{update['version']} (on top of #{flake})")
            dir = write_update_flake(flake, update)
            # fetches the release tarball; everything else is pinned by the shipped flake's lock
            stream(log, nix || find_nix, "flake", "lock", dir)
            ref = "#{dir}##{attr}"
          else
            say(log, "== ampberry redeploy #{Ampberry::VERSION} - flake #{flake}")
            ref = "#{flake}##{attr}"
          end
          sm = system_manager || find_system_manager(log)
          stream(log, "#{sm}/bin/system-manager", "switch", "--flake", ref)
          record_system_path(log, sm)
          stream(log, *(provision_cmd || default_follow_up(update)))
          say(log, "== #{kind} finished in #{(Time.now - started).round}s")
          write_state("state" => "done", "kind" => kind, "started_at" => started.utc.iso8601, "finished_at" => Time.now.utc.iso8601, "exit" => 0)
          true
        rescue StandardError => e
          say(log, "== #{kind} FAILED: #{e.message}")
          write_state("state" => "failed", "kind" => kind, "started_at" => started.utc.iso8601, "finished_at" => Time.now.utc.iso8601,
                      "exit" => 1, "error" => e.message)
          false
        ensure
          log.close
        end
      end

      private

      def kind_of(update) = update ? "update-shairport" : "redeploy"

      def check_update(update)
        u = { "version" => update["version"].to_s, "tag" => (update["tag"] || update["version"]).to_s }
        u.each { |k, v| raise Ampberry::Error, "update-shairport: bad #{k} '#{v}'" unless v.match?(RELEASE_RE) }
        u
      end

      # After a redeploy: provision. After an update: refresh the update cache (as the ampberry
      # user, through its own unit) so the UI's badge turns green.
      def default_follow_up(update)
        update ? ["systemctl", "start", "ampberry-updates.service"] : ["/run/system-manager/sw/bin/ampberry", "provision"]
      end

      # /var/lib/ampberry/shairport-update/flake.nix: the shipped flake (a path: input to its store
      # copy — the store path itself, or ?dir= when the flake lives in a subdirectory of it) +
      # the upstream release, through lib.withShairport.
      def write_update_flake(flake, update)
        src = File.realpath(flake) # /nix/store/…-source or /nix/store/…-source/<subdir>
        input = File.basename(File.dirname(src)) == "store" ? "path:#{src}" : "path:#{File.dirname(src)}?dir=#{File.basename(src)}"
        rel = release_info
        dir = Ampberry.path(:update_flake)
        FileUtils.mkdir_p(dir)
        File.write(File.join(dir, "flake.nix"), <<~NIX)
          # Written by `ampberry redeploy run --update-shairport`. The shipped flake with a newer
          # shairport-sync release on top; Redeploy (from /opt/ampberry) returns to the pinned one.
          {
            description = "#{Ampberry.device['pretty_name']} with shairport-sync #{update['version']}";
            inputs.ampberry.url = "#{input}";
            inputs.shairport-src = {
              url = "github:#{UPSTREAM}/#{update['tag']}";
              flake = false;
            };
            outputs =
              { ampberry, shairport-src, ... }:
              ampberry.lib.withShairport {
                src = shairport-src;
                version = "#{update['version']}";
                device = "#{Ampberry.device['id']}";
                build = "#{rel['BUILD']}";
                flakeVersion = "#{rel['FLAKE_VERSION']}";
              };
          }
        NIX
        lock = File.join(dir, "flake.lock")
        File.unlink(lock) if File.exist?(lock) # re-lock every time: the shipped flake may have moved
        dir
      end

      # BUILD / FLAKE_VERSION of the running system (/etc/ampberry/release), passed through to the
      # update flake so the device keeps reporting its real build number.
      def release_info
        info = { "BUILD" => "dev", "FLAKE_VERSION" => "unknown" }
        File.foreach(Ampberry.path(:release)) do |line|
          k, v = line.chomp.split("=", 2)
          next unless k && v

          v = v.delete_prefix('"').delete_suffix('"')
          info[k] = v if info.key?(k) && v.match?(RELEASE_RE)
        end
        info
      rescue SystemCallError
        info
      end

      def find_nix
        live = File.join(Ampberry.root, NIX)
        File.executable?(live) ? live : "nix"
      end

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
        # child output → the redeploy log file AND our stdout (the journal → the live appliance log).
        # The bytes are tagged UTF-8 as they are (never transcoded): the tools run with
        # Encoding.default_internal set, and nix prints "…" — "\xE2" from ASCII-8BIT to UTF-8 (2026-10-09).
        reader, writer = IO.pipe
        pid = Process.spawn(*cmd, out: writer, err: writer, in: File::NULL)
        writer.close
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TIMEOUT
        status = nil
        loop do
          ready, = IO.select([reader], nil, nil, 0.5)
          if ready
            begin
              chunk = reader.read_nonblock(65_536).force_encoding(Encoding::UTF_8)
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
              log.write(reader.read.to_s.force_encoding(Encoding::UTF_8))
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
