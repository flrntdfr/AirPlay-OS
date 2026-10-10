// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "controllers"
import "@hotwired/turbo-rails"

// one page: Settings is an overlay (Turbo Frame inside a Sheet); no Drive navigation, no streams
import { Turbo } from "@hotwired/turbo-rails"
Turbo.session.drive = false
