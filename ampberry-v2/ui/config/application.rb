# frozen_string_literal: true

require_relative "boot"

require "rails"
require "action_controller/railtie"
require "action_view/railtie"
require "propshaft"
# UI stack: Phlex components (RubyUI = shadcn/ui port), Stimulus via importmap, Tailwind classes
require "phlex-rails"
require "ruby_ui"
require "importmap-rails"
require "stimulus-rails"
require "turbo-rails"

require "ampberry"

module AmpberryUi
  class Application < Rails::Application
    config.load_defaults 7.2

    # One-user LAN appliance: no sessions beyond CSRF, no host allow-list, plain logs to journald.
    config.hosts.clear
    config.logger = ActiveSupport::Logger.new($stdout)
    config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")
    config.log_tags = []
    config.eager_load = true
    config.consider_all_requests_local = false
    config.action_controller.perform_caching = false
    config.action_dispatch.show_exceptions = :rescuable
    config.force_ssl = false
    config.assume_ssl = false
    # Propshaft serves app/assets directly; no precompile step on a single-user appliance.
    config.assets.server = true
    config.public_file_server.enabled = true
    config.session_store :cookie_store, key: "_ampberry", same_site: :lax
    config.secret_key_base = ENV["SECRET_KEY_BASE"] if ENV["SECRET_KEY_BASE"]
    config.i18n.default_locale = :en
    config.time_zone = "Europe/Berlin"

    # Paths the UI reads/talks to (overridable for local development)
    config.x.run_dir = ENV.fetch("AMPBERRY_RUN_DIR", "/run/ampberry")
    config.x.control_socket = ENV.fetch("AMPBERRY_CONTROL_SOCKET", "/run/ampberry-control.sock")
    config.x.actions_file = ENV.fetch("AMPBERRY_ACTIONS_FILE", "/etc/ampberry/actions.json")
    config.x.release_file = ENV.fetch("AMPBERRY_RELEASE_FILE", "/etc/ampberry/release")
    config.x.flake_link = ENV.fetch("AMPBERRY_FLAKE_LINK", "/opt/ampberry")
  end
end
