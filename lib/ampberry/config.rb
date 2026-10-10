# frozen_string_literal: true

require "json"
require "tempfile"
require "etc"

module Ampberry
  # Settings model:  /etc/ampberry/defaults.json  (shipped by the Nix flake)
  #                ⊕ /var/lib/ampberry/settings.json (only the keys the user changed; survives re-provisioning)
  #                = effective settings used to render /etc/shairport-sync.conf.
  module Config
    class InvalidSettings < Ampberry::Error
      attr_reader :problems

      def initialize(problems)
        @problems = problems
        super("invalid settings: #{problems.join('; ')}")
      end
    end

    # Keys the UI may change, with validation rules. Everything else in defaults.json is fixed.
    SCHEMA = {
      "name" => { type: :string, min: 1, max: 40, pattern: /\A[^"\\\x00-\x1f]+\z/,
                  help: "1-40 printable characters, no quotes" },
      "password" => { type: :string, min: 0, max: 64, pattern: /\A[^"\\\x00-\x1f]*\z/,
                      help: "up to 64 printable characters, empty = no password" },
      "interpolation" => { type: :enum, values: %w[auto vernier soxr basic] },
      "output_format" => { type: :enum, values: %w[S32_LE S16_LE] },
      "volume_max_db" => { type: :number, min: -30, max: 0 },
      "volume_range_db" => { type: :number, min: 30, max: 150 }
    }.freeze

    class << self
      # ---- generic JSON helpers --------------------------------------------------------------

      def load_json(path)
        data = JSON.parse(File.binread(path))
        raise Ampberry::Error, "#{path}: top level must be a JSON object" unless data.is_a?(Hash)

        data
      rescue JSON::ParserError => e
        raise Ampberry::Error, "invalid JSON in #{path}: #{e.message.lines.first&.strip}"
      rescue Errno::ENOENT, Errno::EACCES => e
        raise Ampberry::Error, "cannot read #{path}: #{e.message}"
      end

      # Atomic write: temp file in the same directory, chmod/chown, rename.
      def save_json_atomic(path, data, mode: 0o644, owner: nil)
        dir = File.dirname(path)
        raise Ampberry::Error, "directory #{dir} does not exist" unless File.directory?(dir)

        tmp = Tempfile.create([".#{File.basename(path)}.", ".tmp"], dir)
        begin
          tmp.binmode
          tmp.write(JSON.pretty_generate(data))
          tmp.write("\n")
          tmp.flush
          tmp.fsync
          tmp.close
          File.chmod(mode, tmp.path)
          chown(tmp.path, owner) if owner
          File.rename(tmp.path, path)
        rescue StandardError
          File.unlink(tmp.path) if File.exist?(tmp.path)
          raise
        end
        path
      end

      # Recursive hash merge: values from +over+ win; nested hashes merge; arrays/scalars replace.
      def merge_deep(base, over)
        result = (base || {}).dup
        (over || {}).each do |k, v|
          result[k] = v.is_a?(Hash) && result[k].is_a?(Hash) ? merge_deep(result[k], v) : v
        end
        result
      end

      # ---- settings ---------------------------------------------------------------------------

      def settings_schema
        SCHEMA.transform_values(&:dup)
      end

      def load_defaults = load_json(Ampberry.path(:defaults))

      def load_settings
        path = Ampberry.path(:settings)
        File.exist?(path) ? load_json(path) : {}
      end

      def effective_settings(defaults: nil, settings: nil)
        merge_deep(defaults || load_defaults, settings || load_settings)
      end

      # Returns a list of human-readable problems (empty when valid).
      def validate_settings(settings)
        return ["settings must be an object"] unless settings.is_a?(Hash)

        settings.keys.sort.flat_map do |k|
          rule = SCHEMA[k.to_s]
          next ["unknown setting '#{k}'"] unless rule

          v = settings[k]
          case rule[:type]
          when :enum
            rule[:values].include?(v) ? [] : ["#{k}: must be one of #{rule[:values].join(', ')}"]
          when :number
            if !v.is_a?(Numeric) && !(v.is_a?(String) && v.match?(/\A-?\d+(?:\.\d+)?\z/))
              ["#{k}: must be a number"]
            elsif v.to_f < rule[:min] || v.to_f > rule[:max]
              ["#{k}: must be between #{rule[:min]} and #{rule[:max]}"]
            else
              []
            end
          else
            if v.is_a?(String) && v.length.between?(rule[:min], rule[:max]) && v.match?(rule[:pattern])
              []
            else
              ["#{k}: #{rule[:help]}"]
            end
          end
        end
      end

      # Persist only schema keys that differ from the defaults; unknown keys are rejected.
      def save_settings(settings, defaults: nil, mode: 0o644, owner: nil)
        problems = validate_settings(settings)
        raise InvalidSettings, problems unless problems.empty?

        defaults ||= load_defaults
        store = settings.sort.to_h.reject { |k, v| same?(v, defaults[k]) }
        save_json_atomic(Ampberry.path(:settings), store, mode: mode, owner: owner)
      end

      private

      def same?(a, b)
        return a.to_f == b.to_f if a.is_a?(Numeric) && b.is_a?(Numeric)

        a == b
      end

      def chown(path, owner)
        user, group = owner.split(":", 2)
        uid = user && !user.empty? ? Etc.getpwnam(user).uid : nil
        gid = group && !group.empty? ? Etc.getgrnam(group).gid : nil
        File.chown(uid, gid, path)
      end
    end
  end
end
