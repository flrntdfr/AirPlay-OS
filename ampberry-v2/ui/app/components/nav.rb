# frozen_string_literal: true

# Top bar, full width: brand at the left edge, the two tabs at the right edge. "Now playing" is the
# page; "Settings" opens an overlay (RubyUI Sheet) that lazy-loads /settings into a Turbo Frame, so
# the box is a single page. Wi‑Fi onboarding (/setup) is deliberately not linked — it is reached
# through the hotspot's captive portal when the box has no network.
class Components::Nav < Components::Base
  def initialize(current:)
    @current = current.to_s
  end

  def view_template
    header(class: "sticky top-0 z-10 border-b bg-background") do
      nav(class: "flex w-full items-baseline justify-between gap-4 px-4 py-3") do
        a(href: root_path, class: "brand font-semibold tracking-tight no-underline") { "Ampberry" }
        div(class: "flex items-baseline gap-5") do
          a(href: root_path, class: [TAB, @current == "player" ? TAB_ACTIVE : TAB_IDLE]) { "Now playing" }
          settings_sheet
        end
      end
    end
  end

  private

  def settings_sheet
    Sheet do
      SheetTrigger(class: "inline-block") do
        button(type: "button", class: [TAB, @current == "settings" ? TAB_ACTIVE : TAB_IDLE]) { "Settings" }
      end
      # the panel itself never scrolls: the frame is a fixed-height column (rigid title bar and
      # stats bar, smooth scrolling only in the middle — see Views::Settings::Show)
      SheetContent(side: :right, class: "flex w-full flex-col overflow-hidden p-0 sm:max-w-md") do
        # eager: the frame lives in the Sheet's <template>, so it loads exactly when the panel opens
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
