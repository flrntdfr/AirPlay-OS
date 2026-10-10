# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = false
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base ||= "development-only-secret-key-base-not-used-on-the-device"
end
