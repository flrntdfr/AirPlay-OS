# frozen_string_literal: true

require "shellwords"

module AirPlayOS
  # Command runner used by every module.
  #   r   = AirPlayOS::Run.run("systemctl", "restart", "shairport-sync", timeout: 60)
  #   out = AirPlayOS::Run.capture("nmcli", "-t", "device", "status")
  # * Commands are argv arrays, never shell strings.
  # * stdout/stderr are read concurrently so large outputs cannot deadlock.
  # * A timeout (default 600 s) kills the child; status 124 is reported, like coreutils timeout.
  # * Run.runner = ->(cmd, opts) { {status:, out:, err:} } lets tests mock all execution.
  # * Run.dry_run = true skips commands unless they are marked read_only: true.
  module Run
    class CommandError < AirPlayOS::Error
      attr_reader :result

      def initialize(message, result = nil)
        super(message)
        @result = result
      end
    end

    Result = Struct.new(:status, :out, :err, :cmd, :dry_run, keyword_init: true) do
      def success? = status.zero?
    end

    MAX_ERR_IN_MESSAGE = 2000

    class << self
      attr_accessor :runner, :dry_run, :logger

      # Run and return a Result without raising.
      def try_run(*cmd, **opts)
        raise ArgumentError, "a command is required" if cmd.empty?

        cmd = cmd.map(&:to_s)
        display = shell_quote(cmd)
        logger&.call("run: #{display}") unless opts[:quiet]
        if dry_run && !opts[:read_only]
          logger&.call("dry-run: skipped")
          return Result.new(status: 0, out: "", err: "", cmd: display, dry_run: true)
        end
        raw = runner ? runner.call(cmd, opts) : exec(cmd, opts)
        Result.new(status: raw[:status] || 0, out: raw[:out] || "", err: raw[:err] || "", cmd: display, dry_run: false)
      end

      # Run and raise unless the exit status is acceptable (ok: [0] by default).
      def run(*cmd, ok: [0], **opts)
        r = try_run(*cmd, **opts)
        return r if ok.include?(r.status)

        err = r.err.to_s
        err = "...#{err[-MAX_ERR_IN_MESSAGE..]}" if err.length > MAX_ERR_IN_MESSAGE
        err = err.rstrip
        raise CommandError.new("command failed (exit #{r.status}): #{r.cmd}#{err.empty? ? '' : "\n#{err}"}", r)
      end

      # Run (read-only by default) and return stdout.
      def capture(*cmd, chomp: true, **opts)
        opts = { read_only: true }.merge(opts)
        out = run(*cmd, **opts).out
        chomp ? out.chomp : out
      end

      # Display form for logs only; nothing is ever passed through a shell.
      def shell_quote(words)
        words.map { |w| w.match?(%r{\A[\w@%+=:,./-]+\z}) ? w : Shellwords.escape(w) }.join(" ")
      end

      private

      def exec(cmd, opts)
        timeout = opts.fetch(:timeout, 600)
        env = (opts[:env] || {}).transform_keys(&:to_s).transform_values(&:to_s)
        in_r, in_w = IO.pipe
        out_r, out_w = IO.pipe
        err_r, err_w = IO.pipe
        begin
          pid = Process.spawn(env, *cmd, in: in_r, out: out_w, err: err_w)
        rescue SystemCallError => e
          [in_r, in_w, out_r, out_w, err_r, err_w].each(&:close)
          raise CommandError.new("cannot execute '#{cmd.first}': #{e.message}")
        end
        in_r.close
        out_w.close
        err_w.close
        begin
          in_w.write(opts[:stdin]) if opts[:stdin] && !opts[:stdin].empty?
        rescue Errno::EPIPE
          # child did not read stdin; fine
        end
        in_w.close

        buf = { out_r => String.new, err_r => String.new }
        readers = [out_r, err_r]
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        timed_out = false
        until readers.empty?
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if remaining <= 0
            timed_out = true
            kill(pid, "TERM")
            sleep 0.5
            kill(pid, "KILL")
            break
          end
          ready, = IO.select(readers, nil, nil, remaining)
          next unless ready

          ready.each do |io|
            begin
              buf[io] << io.read_nonblock(65_536)
            rescue IO::WaitReadable
              next
            rescue EOFError
              readers.delete(io)
            end
          end
        end
        _, status = Process.wait2(pid)
        [out_r, err_r].each { |io| io.close unless io.closed? }
        code = if timed_out then 124
               elsif status.exitstatus then status.exitstatus
               else 128 + status.termsig.to_i
               end
        buf[err_r] << "\n[timed out after #{timeout}s]" if timed_out
        { status: code, out: buf[out_r], err: buf[err_r] }
      end

      def kill(pid, sig)
        Process.kill(sig, pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end
    end
  end
end
