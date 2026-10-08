# frozen_string_literal: true

Rails.application.routes.draw do
  root "player#index"
  get "now-playing", to: "player#now_playing", defaults: { format: :json }
  post "player/toggle", to: "player#toggle", as: :player_toggle # play/pause → DACP to the sender
  get "cover/:file", to: "player#cover", constraints: { file: /cover-[0-9a-f]{40}\.(?:jpg|png|bin)/ }

  get "settings", to: "settings#show"
  post "settings", to: "settings#update"

  get "setup", to: "setup#show"
  post "setup/scan", to: "setup#scan"
  post "setup/connect", to: "setup#connect"

  # The control API, as JSON: list actions, trigger one.
  namespace :api do
    get "actions", to: "actions#index"
    post "actions/:id", to: "actions#create", constraints: { id: /[a-z][a-z0-9-]{0,40}/ }
    get "now-playing", to: "/player#now_playing", defaults: { format: :json }
    get "log", to: "log#show"
  end

  get "health", to: "health#show"
  # browsers ask for it regardless of <link rel="icon">; keep it out of the error log
  get "favicon.ico", to: proc { [204, {}, []] }
end
