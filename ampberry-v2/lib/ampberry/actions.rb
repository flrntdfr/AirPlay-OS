# frozen_string_literal: true

module Ampberry
  # The allow-list of things the unprivileged web UI may ask root to do.
  #   built-in actions: code here, with declared, validated parameters
  #   custom actions:   /etc/ampberry/actions.json (root-owned, shipped by the Nix flake):
  #                     { "actions": [ { "id", "label", "description", "exec": [argv...],
  #                                      "timeout", "confirm", "danger" } ] }
  # exec must be an argv whose program is an absolute path; it is never passed through a shell and
  # never receives client-supplied arguments. Unknown ids and undeclared parameters are rejected.
  module Actions
    ID_RE = /\A[a-z][a-z0-9-]{0,40}\z/
    DEFAULT_TIMEOUT = 120

    BUILTIN = {
      "settings-show" => { label: "Show settings", params: {},
                           code: ->(_p) { { "settings" => Config.effective_settings, "schema" => Config.settings_schema } } },
      "settings-apply" => { label: "Apply settings", params: { "settings" => :hash },
                            code: lambda { |p|
                              s = (p["settings"] || {}).transform_keys(&:to_s)
                              problems = Config.validate_settings(s)
                              raise Ampberry::Error, "invalid settings: #{problems.join('; ')}" unless problems.empty?

                              eff = Config.effective_settings.select { |k, _| Config::SCHEMA.key?(k) }
                              { "settings" => Settings.apply(settings: eff.merge(s)) }
                            } },
      "wifi-scan" => { label: "Scan Wi-Fi networks", params: {}, code: ->(_p) { { "networks" => Wifi.scan } } },
      "wifi-status" => { label: "Wi-Fi status", params: {}, code: ->(_p) { { "status" => Wifi.status } } },
      "wifi-connect" => { label: "Join a Wi-Fi network", params: { "ssid" => :string, "psk" => :string }, confirm: true,
                          code: ->(p) { { "status" => Wifi.connect(p["ssid"].to_s, p["psk"].to_s) } } },
      "wifi-hotspot-off" => { label: "Stop onboarding hotspot", params: {}, code: ->(_p) { { "changed" => Wifi.hotspot_off } } },
      "restart-airplay" => { label: "Restart AirPlay", params: {},
                             code: lambda { |_p|
                               Run.run("systemctl", "restart", "nqptp", "shairport-sync", "avahi-daemon", timeout: 90)
                               { "restarted" => %w[nqptp shairport-sync avahi-daemon] }
                             } },
      "redeploy" => { label: "Redeploy", params: {}, confirm: true, danger: true,
                      description: "Re-applies the Nix flake from /opt/ampberry (system-manager switch) and re-runs provisioning in the background; the log streams behind the page.",
                      code: ->(_p) { Redeploy.start(reason: "web ui") } },
      "clean-reboot" => { label: "Clean reboot (re-provision)", params: { "reset_settings" => :bool }, confirm: true, danger: true,
                          code: lambda { |p|
                            System.clean_reboot(reset_settings: p["reset_settings"] ? true : false, no_reboot: true)
                            # the reboot runs after the response has been written (the caller gets an answer first)
                            { "rebooting" => true, after: -> { Run.run("systemctl", "reboot", timeout: 60) } }
                          } }
    }.freeze

    class << self
      def builtin_ids = BUILTIN.keys.sort

      # Custom actions from the config file, validated. Returns { id => spec }.
      def load_custom(path: Ampberry.path(:actions))
        return {} unless File.exist?(path)

        cfg = Config.load_json(path)
        list = cfg.fetch("actions", [])
        raise Ampberry::Error, "#{path}: 'actions' must be an array" unless list.is_a?(Array)

        list.each_with_object({}) do |a, custom|
          raise Ampberry::Error, "#{path}: every action must be an object" unless a.is_a?(Hash)

          id = a["id"].to_s
          raise Ampberry::Error, "#{path}: invalid action id '#{id}'" unless id.match?(ID_RE)
          raise Ampberry::Error, "#{path}: action '#{id}' collides with a built-in" if BUILTIN.key?(id)
          raise Ampberry::Error, "#{path}: action '#{id}' defined twice" if custom.key?(id)

          exec = a["exec"]
          unless exec.is_a?(Array) && !exec.empty? && exec.all?(String)
            raise Ampberry::Error, "#{path}: action '#{id}': exec must be a non-empty array of strings"
          end
          raise Ampberry::Error, "#{path}: action '#{id}': exec program must be an absolute path" unless exec.first.start_with?("/")

          timeout = a.fetch("timeout", DEFAULT_TIMEOUT)
          raise Ampberry::Error, "#{path}: action '#{id}': timeout must be 1..3600" unless timeout.is_a?(Integer) && timeout.between?(1, 3600)

          custom[id] = { "id" => id, "label" => (a["label"] || id).to_s, "description" => a["description"].to_s,
                         "exec" => exec, "timeout" => timeout, "confirm" => a["confirm"] ? true : false,
                         "danger" => a["danger"] ? true : false, "custom" => true }
        end
      end

      # Public catalogue for the UI (no code, no exec details).
      def list(path: Ampberry.path(:actions))
        builtins = BUILTIN.sort.map do |id, b|
          { "id" => id, "label" => b[:label], "description" => b[:description].to_s, "params" => b[:params].transform_values(&:to_s),
            "confirm" => b[:confirm] ? true : false, "danger" => b[:danger] ? true : false, "custom" => false }
        end
        customs = load_custom(path: path).sort.map do |_id, c|
          c.slice("id", "label", "description", "confirm", "danger", "custom")
        end
        builtins + customs
      end

      # Returns { "ok" => true, "action" => id, "result" => {...} [, after: proc] }
      #      or { "ok" => false, "action" => id, "error" => "..." [, "output" => "..."] }.
      def run_action(id, params = {}, peer: nil, path: Ampberry.path(:actions))
        params ||= {}
        return err(id, "invalid action id") unless id.is_a?(String) && id.match?(ID_RE)
        return err(id, "params must be an object") unless params.is_a?(Hash)

        params = params.transform_keys(&:to_s)
        if (b = BUILTIN[id])
          bad = params.keys - b[:params].keys
          return err(id, "unexpected parameter(s): #{bad.join(' ')}") unless bad.empty?

          b[:params].each do |k, want|
            next unless params.key?(k)

            v = params[k]
            return err(id, "parameter '#{k}' must be a string") if want == :string && !v.is_a?(String)
            return err(id, "parameter '#{k}' must be an object") if want == :hash && !v.is_a?(Hash)
            return err(id, "parameter '#{k}' must be a boolean") if want == :bool && ![true, false, nil].include?(v)
          end
          Log.info("action #{id}#{peer ? " (uid #{peer})" : ''}")
          begin
            result = b[:code].call(params)
          rescue StandardError => e
            Log.warning("action #{id} failed: #{e.message}")
            return err(id, e.message)
          end
          after = result.delete(:after)
          out = { "ok" => true, "action" => id, "result" => result }
          out[:after] = after if after
          return out
        end

        custom = begin
          load_custom(path: path)
        rescue Ampberry::Error => e
          return err(id, "actions config invalid: #{e.message}")
        end
        c = custom[id] or return err(id, "unknown action")
        return err(id, "custom actions take no parameters") unless params.empty?

        Log.info("action #{id} (custom)#{peer ? " (uid #{peer})" : ''}")
        r = Run.try_run(*c["exec"], timeout: c["timeout"])
        output = (r.out.to_s + r.err.to_s)[-4000..] || (r.out.to_s + r.err.to_s)
        unless r.status.zero?
          Log.warning("action #{id} exited #{r.status}")
          return { "ok" => false, "action" => id, "error" => "exit status #{r.status}", "output" => output }
        end
        { "ok" => true, "action" => id, "result" => { "output" => output } }
      end

      private

      def err(id, msg) = { "ok" => false, "action" => id.to_s, "error" => msg }
    end
  end
end
