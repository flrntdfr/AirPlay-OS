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

require "airplay_os"

module AirPlayOSUi
  class Application < Rails::Application
    config.load_defaults 7.2

    # airplay_os_bridge.rb defines AirPlayOSBridge; the default inflection would expect AirplayOsBridge.
    Rails.autoloaders.each { |l| l.inflector.inflect("airplay_os_bridge" => "AirPlayOSBridge") }

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
    config.session_store :cookie_store, key: "_airplay_os", same_site: :lax
    config.secret_key_base = ENV["SECRET_KEY_BASE"] if ENV["SECRET_KEY_BASE"]
    config.i18n.default_locale = :en
    config.time_zone = "Europe/Berlin"

    # Paths the UI reads/talks to (overridable for local development)
    config.x.run_dir = ENV.fetch("AIRPLAY_OS_RUN_DIR", "/run/airplay-os")
    config.x.control_socket = ENV.fetch("AIRPLAY_OS_CONTROL_SOCKET", "/run/airplay-os-control.sock")
    config.x.actions_file = ENV.fetch("AIRPLAY_OS_ACTIONS_FILE", "/etc/airplay-os/actions.json")
    config.x.release_file = ENV.fetch("AIRPLAY_OS_RELEASE_FILE", "/etc/airplay-os/release")
    config.x.flake_link = ENV.fetch("AIRPLAY_OS_FLAKE_LINK", "/opt/airplay-os")
    config.x.shairport_conf = ENV.fetch("AIRPLAY_OS_SHAIRPORT_CONF", "/etc/shairport-sync.conf")
  end
end
