# frozen_string_literal: true

# Home: the live log fills the screen (body.player makes the backdrop the page, scrollable — see
# app/assets/tailwind/application.css); the only content is the player bar flush at the bottom:
# cover thumbnail (tap → full-screen Dialog), title / artist / status, a thin progress line, and
# play/pause (DACP back to the sender). player.js polls /now-playing and updates the ids below;
# #player carries the state classes active / idle / playing / shown / has-cover.
class Views::Player::Index < Views::Base
  include Phlex::Rails::Helpers::FormAuthenticityToken

  def initialize(now:, release:)
    @now = now
    @release = release
  end

  def view_template
    # shown only while playing at render time; player.js then applies the "paused from here" rule
    state = [@now["active"] ? "active" : "idle", ("playing" if @now["playing"]), ("shown" if @now["playing"]), ("has-cover" if cover)].compact.join(" ")

    div(id: "player", class: "fixed inset-x-0 bottom-0 z-10 border-t bg-background #{state}",
        data: { now_playing_url: now_playing_path, toggle_url: player_toggle_path, cover_base: "/cover/", csrf: form_authenticity_token }) do
      div(id: "progress", class: "player-progress h-0.5 w-full bg-foreground/20", aria_hidden: "true") do
        div(id: "bar", class: "progress-bar h-full bg-foreground")
      end
      div(class: "mx-auto flex max-w-2xl items-center gap-3 px-4 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]") do
        cover_dialog
        div(class: "min-w-0 flex-1") do
          p(id: "title", class: "truncate text-base font-semibold leading-tight") { title_text }
          p(id: "artist", class: "truncate text-sm text-muted-foreground") { artist_text }
          p(id: "status", class: "truncate text-xs text-muted-foreground") { status_text }
        end
        button(id: "toggle", type: "button", aria_label: "Play / pause", disabled: !@now["active"],
               class: "grid h-12 w-12 shrink-0 place-items-center rounded-full border bg-background text-foreground active:bg-foreground active:text-background disabled:opacity-30") do
          svg(class: "icon-play h-5 w-5 translate-x-px", viewBox: "0 0 24 24", fill: "currentColor", aria_hidden: "true") { |s| s.path(d: "M8 5v14l11-7z") }
          svg(class: "icon-pause h-5 w-5", viewBox: "0 0 24 24", fill: "currentColor", aria_hidden: "true") { |s| s.path(d: "M6 5h4v14H6zm8 0h4v14h-4z") }
        end
      end
    end
  end

  private

  def cover = @now["cover_file"] && "/cover/#{@now["cover_file"]}"

  # Thumbnail in the bar; tapping it opens the artwork full-screen in a Dialog (native <dialog>).
  def cover_dialog
    Dialog do
      DialogTrigger(class: "cover-trigger shrink-0") do
        img(id: "cover", src: cover, alt: "Cover art", class: "h-12 w-12 rounded-sm border object-cover")
      end
      DialogContent(size: :full, class: "h-dvh max-h-none w-screen rounded-none border-0 bg-black p-0 shadow-none") do
        img(id: "cover-full", src: cover, alt: "Cover art", class: "h-full w-full object-contain",
            data: { action: "click->ruby-ui--dialog#dismiss" })
      end
    end
  end

  def title_text
    return @release["NAME"] || "Ampberry" unless @now["active"]

    @now["title"].presence || "…"
  end

  def artist_text = [@now["artist"].presence, @now["album"].presence].compact.join(" · ")

  def status_text
    return "Ready for AirPlay" unless @now["active"]

    s = @now["playing"] ? "Playing" : "Paused"
    @now["client"].present? ? "#{s} · from #{@now["client"]}" : s
  end
end
