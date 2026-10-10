#!/usr/bin/env ruby
# frozen_string_literal: true

# Render the cloud-init seed (user-data, network-config, meta-data) for one device from
# cloud-init/*.tmpl, devices/<id>.json and secrets.env into an output directory (default: build/).
# Run via tools/build-image.sh / tools/apply-live.sh or:
#   nix shell nixpkgs#ruby_3_4 --command ruby tools/build-user-data.rb --device airplay-os --out build
#
# secrets.env is a KEY="value" file (shell style). Required: SSH_AUTHORIZED_KEYS (one key per
# line inside the quotes); for a Wi‑Fi device also WIFI_SSID, WIFI_PSK, SETUP_PSK (the onboarding
# hotspot). Optional: WIFI_COUNTRY (DE), TIMEZONE (Europe/Berlin), PI_PASSWORD_HASH (crypt(3)
# hash; keeps the serial console usable).

require "json"
require "optparse"
require "fileutils"
require "time"

# the image build and systemd units may run without LANG: treat everything as UTF-8
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

root = File.expand_path("..", __dir__)
opts = { out: File.join(root, "build"), secrets: File.join(root, "secrets.env"), device: "ampberry" }
OptionParser.new do |o|
  o.on("--out DIR") { |v| opts[:out] = v }
  o.on("--secrets FILE") { |v| opts[:secrets] = v }
  o.on("--device ID", "devices/<ID>.json (default: ampberry)") { |v| opts[:device] = v }
end.parse!

abort "secrets file not found: #{opts[:secrets]} (copy secrets.env.example)" unless File.exist?(opts[:secrets])
device_file = File.join(root, "docs", "devices", "#{opts[:device]}.json")
abort "unknown device #{opts[:device]} (no #{device_file})" unless File.exist?(device_file)
device = JSON.parse(File.read(device_file))
wifi = device["wifi"] ? true : false

# --- parse KEY="value" / KEY=value lines (values may span lines inside double quotes) --------------
secrets = {}
text = File.read(opts[:secrets])
text.scan(/^\s*(?:export\s+)?([A-Z][A-Z0-9_]*)=("(?:[^"\\]|\\.)*"|'[^']*'|[^\n#]*)/m) do |key, raw|
  value = raw.strip
  value = if value.start_with?('"') then value[1..-2].gsub(/\\(["\\])/, '\1')
          elsif value.start_with?("'") then value[1..-2]
          else value
          end
  secrets[key] = value
end

required = %w[SSH_AUTHORIZED_KEYS]
required += %w[WIFI_SSID WIFI_PSK SETUP_PSK] if wifi
required.each do |k|
  abort "#{k} missing or empty in #{opts[:secrets]}" if secrets[k].to_s.strip.empty?
end
if wifi
  abort "SETUP_PSK must be 8..63 characters" unless secrets["SETUP_PSK"].length.between?(8, 63)
  abort "WIFI_PSK must be an 8..63 character passphrase or a 64-digit hex PSK" unless secrets["WIFI_PSK"].length.between?(8, 63) || secrets["WIFI_PSK"].match?(/\A\h{64}\z/)
end

def yaml_q(s) = %("#{s.gsub(/[\\"]/) { "\\#{$&}" }}")

keys = secrets["SSH_AUTHORIZED_KEYS"].lines.map(&:strip).reject(&:empty?)
abort "SSH_AUTHORIZED_KEYS has no keys" if keys.empty?
keys.each { |k| abort "not an SSH public key: #{k[0, 40]}…" unless k.match?(/\A(ssh-(ed25519|rsa)|ecdsa-sha2-nistp\d+|sk-\S+) [A-Za-z0-9+\/=]+/) }

hash = secrets["PI_PASSWORD_HASH"].to_s.strip
wifi_section =
  if wifi
    <<~YAML.chomp
      wifis:
        wlan0:
          dhcp4: true
          regulatory-domain: #{yaml_q(secrets.fetch('WIFI_COUNTRY', 'DE'))}
          access-points:
            #{yaml_q(secrets['WIFI_SSID'])}:
              password: #{yaml_q(secrets['WIFI_PSK'])}
          optional: true
    YAML
  else
    ""
  end
vars = {
  "HOSTNAME" => device["hostname"],
  "PRETTY_NAME" => device["pretty_name"],
  "TIMEZONE" => secrets.fetch("TIMEZONE", "Europe/Berlin"),
  "PI_LOCK_PASSWD" => hash.empty? ? "true" : "false",
  "PI_PASSWD_LINE" => hash.empty? ? "" : "    hashed_passwd: #{yaml_q(hash)}",
  "SSH_KEYS_YAML" => keys.map { |k| "      - #{yaml_q(k)}" }.join("\n"),
  "SETUP_PSK_JSON" => JSON.generate(secrets["SETUP_PSK"].to_s),
  "WIFI_SECTION" => wifi_section.gsub(/^/, "  ").rstrip
}

def render(template, vars)
  out = template.gsub(/\{\{([A-Z_]+)\}\}/) do
    vars.fetch(Regexp.last_match(1)) { abort "no value for {{#{Regexp.last_match(1)}}}" }
  end
  out.gsub(/^ *\n(?=\n)/, "").gsub(/\n{3,}/, "\n\n") # drop lines that became empty (no hash, no Wi‑Fi)
end

FileUtils.mkdir_p(opts[:out])
File.write(File.join(opts[:out], "user-data"), render(File.read(File.join(root, "cloud-init/user-data.tmpl")), vars))
File.write(File.join(opts[:out], "network-config"), render(File.read(File.join(root, "cloud-init/network-config.tmpl")), vars))
File.write(File.join(opts[:out], "meta-data"), "instance-id: #{device['hostname']}-#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}\nlocal-hostname: #{device['hostname']}\n")
FileUtils.chmod(0o600, Dir.glob(File.join(opts[:out], "{user-data,network-config}")))
puts "rendered #{opts[:out]}/{user-data,network-config,meta-data} for #{device['id']} (#{keys.size} SSH key(s), #{wifi ? 'Wi‑Fi' : 'Ethernet only'}, console password #{hash.empty? ? 'locked' : 'set'})"
