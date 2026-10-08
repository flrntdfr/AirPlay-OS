# frozen_string_literal: true

require "json"
require "socket"
require "etc"

module Ampberry
  # The control API between the unprivileged web UI and root.
  #
  # Server side: systemd socket activation (Accept=yes) hands one connection per invocation on
  # STDIN/STDOUT (`ampberry control handle`, runs as root):
  #   request:  one JSON object on a single line, e.g. {"action":"wifi-scan","params":{}}
  #   response: one JSON object, newline-terminated, then the connection closes
  # Trust boundary: the socket is root:ampberry 0660 (systemd), the peer uid is checked again via
  # SO_PEERCRED, requests are size- and time-limited, and only Ampberry::Actions' allow-list runs.
  #
  # Client side (Rails): Ampberry::Control::Client.new.call("wifi-scan")
  module Control
    MAX_REQUEST = 64 * 1024
    READ_TIMEOUT = 10
    ALLOWED_USERS = %w[root ampberry].freeze

    class << self
      # uid of the connected peer, or nil when the handle is not a Unix socket.
      def peer_uid(io)
        return nil unless defined?(Socket::SO_PEERCRED)

        sock = if io.is_a?(BasicSocket)
                 io
               elsif io.respond_to?(:fileno) && io.fileno
                 s = Socket.for_fd(io.fileno)
                 s.autoclose = false # we only borrow the descriptor
                 s
               end
        return nil unless sock

        cred = sock.getsockopt(Socket::SOL_SOCKET, Socket::SO_PEERCRED)
        _pid, uid, _gid = cred.data.unpack("iii")
        uid
      rescue StandardError
        nil
      end

      # Handle exactly one request. Returns 0 on success, 1 otherwise.
      def handle_stream(input, output, peer_uid: :detect, allowed_users: ALLOWED_USERS, read_timeout: READ_TIMEOUT)
        uid = peer_uid == :detect ? self.peer_uid(input) : peer_uid
        if uid
          name = begin
            Etc.getpwuid(uid).name
          rescue ArgumentError
            ""
          end
          unless allowed_users.include?(name)
            Log.warning("control: rejected connection from uid #{uid} (#{name})")
            return respond(output, { "ok" => false, "error" => "not allowed" })
          end
        end

        line = begin
          read_request(input, read_timeout)
        rescue Ampberry::Error => e
          return respond(output, { "ok" => false, "error" => e.message })
        end
        return respond(output, { "ok" => false, "error" => "empty request" }) if line.nil? || line.strip.empty?

        req = begin
          JSON.parse(line.lines.first)
        rescue JSON::ParserError
          return respond(output, { "ok" => false, "error" => "invalid JSON" })
        end
        return respond(output, { "ok" => false, "error" => "request must be an object" }) unless req.is_a?(Hash)

        res = Actions.run_action(req["action"], req["params"] || {}, peer: uid)
        after = res.delete(:after)
        rc = respond(output, res)
        after&.call # e.g. reboot, once the client has its answer
        rc
      end

      private

      def read_request(input, timeout)
        # StringIO (tests) and other non-IO objects: plain read, no select()
        return input.read.to_s unless input.respond_to?(:to_io) && input.to_io.is_a?(IO)

        buf = String.new
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          raise Ampberry::Error, "timeout" if remaining <= 0

          ready, = IO.select([input.to_io], nil, nil, remaining)
          raise Ampberry::Error, "timeout" unless ready

          begin
            buf << input.read_nonblock(4096)
          rescue IO::WaitReadable
            next
          rescue EOFError
            break
          end
          raise Ampberry::Error, "request too large" if buf.bytesize > MAX_REQUEST
          break if buf.include?("\n")
        end
        buf
      end

      def respond(output, data)
        output.write("#{JSON.generate(data)}\n")
        output.flush if output.respond_to?(:flush)
        data["ok"] ? 0 : 1
      end
    end

    # Used by the web UI (unprivileged). Never loads the root-side modules.
    class Client
      def initialize(socket_path: Ampberry.path(:control_socket), timeout: 130)
        @socket_path = socket_path
        @timeout = timeout
      end

      def call(action, params = {})
        UNIXSocket.open(@socket_path) do |sock|
          sock.write("#{JSON.generate('action' => action, 'params' => params)}\n")
          sock.flush
          ready, = IO.select([sock], nil, nil, @timeout)
          raise Ampberry::Error, "control: no answer within #{@timeout}s" unless ready

          line = sock.gets
          raise Ampberry::Error, "control: connection closed without an answer" if line.nil?

          JSON.parse(line)
        end
      rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::EACCES => e
        { "ok" => false, "action" => action, "error" => "control socket unavailable (#{e.class.name.split('::').last})" }
      end
    end
  end
end
