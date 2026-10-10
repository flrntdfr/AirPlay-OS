# frozen_string_literal: true

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../Gemfile", __dir__)
require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])

# The shared AirPlay OS library (control client, catalogue reading); the root-side modules are
# never executed here, the UI only talks to the control socket.
$LOAD_PATH.unshift(ENV.fetch("AIRPLAY_OS_LIB", File.expand_path("../../lib", __dir__)))
