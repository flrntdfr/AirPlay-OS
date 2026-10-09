# frozen_string_literal: true

# Top bar, full width, fixed height (the Settings pane hangs below it): brand at the left edge,
# the two tabs at the right edge. "• Live" is the page — the dot is the receiver's state: green
# ready for a sender, red (bouncing) while playing, orange while paused, grey when the state is
# unknown (player.js keeps it current). "Settings" opens a pane under the bar (RubyUI Sheet) that
# loads /settings into a Turbo Frame, so the box is a single page. Wi‑Fi onboarding (/setup) is
# deliberately not linked — it is reached through the hotspot's captive portal.
class Components::Nav < Components::Base
  # name: the receiver's AirPlay name — the brand at the left is the box's own name (a saved
  # rename in Settings updates it in place, autosave_controller.js)
  def initialize(current:, now: {}, name: "Ampberry")
    @current = current.to_s
    @now = now
    @name = name.presence || "Ampberry"
  end

  def view_template
    header(class: "fixed inset-x-0 top-0 z-30 h-12 border-b bg-background") do
      nav(class: "flex h-full w-full items-center justify-between gap-4 px-4") do
        a(href: root_path, class: "brand font-semibold tracking-tight no-underline", data: { brand: true }) { @name }
        div(class: "flex items-center gap-5") do
          a(href: root_path, class: [TAB, @current == "player" ? TAB_ACTIVE : TAB_IDLE]) do
            span(id: "live-dot", class: "live-dot #{live_state}", aria_hidden: "true") { "•" }
            plain " Live"
          end
          settings_sheet
        end
      end
    end
  end

  private

  def live_state
    return "unknown" if @now["stale"]
    return "ready" unless @now["active"]

    @now["playing"] ? "playing" : "paused"
  end

  def settings_sheet
    Sheet(class: "inline-block") do
      SheetTrigger(class: "inline-block") do
        button(type: "button", class: [TAB, "cursor-pointer", @current == "settings" ? TAB_ACTIVE : TAB_IDLE]) { "Settings" }
      end
      # the pane itself never scrolls: the frame is a fixed-height column (rigid stats bar at the
      # bottom, smooth scrolling only above it — see Views::Settings::Show)
      SheetContent(side: :right, class: "flex w-full flex-col overflow-hidden p-0 sm:max-w-md") do
        # eager: the frame lives in the Sheet's <template>, so it loads exactly when the pane opens
        turbo_frame(id: "settings", src: settings_path, loading: "eager", class: "flex h-full min-h-0 flex-col") do
          # spinner until the frame arrives
          div(class: "grid flex-1 place-items-center", role: "status", aria_label: "Loading settings") do
            svg(class: "h-6 w-6 animate-spin text-muted-foreground", viewBox: "0 0 24 24", fill: "none", aria_hidden: "true") do |s|
              s.circle(cx: "12", cy: "12", r: "10", stroke: "currentColor", stroke_width: "3", class: "opacity-25")
              s.path(d: "M22 12a10 10 0 0 1-10 10", stroke: "currentColor", stroke_width: "3", stroke_linecap: "round")
            end
          end
        end
      end
    end
  end
end
