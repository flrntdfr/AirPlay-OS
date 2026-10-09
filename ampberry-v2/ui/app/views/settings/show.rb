# frozen_string_literal: true

# Settings, in this order: AirPlay (name saves as you type; password with an eye and a "+"),
# Restart AirPlay, Sound (saves 1 s after a change), Reboot + Redeploy (armed by "Yes" boxes).
# No Apply buttons, no help text (tooltips on the sound settings). No volume control here on
# purpose: the phone sets the level, `volume_max_db` is the ceiling.
class Views::Settings::Show < Views::Base
  include Phlex::Rails::Helpers::FormAuthenticityToken

  TIPS = {
    "volume_max_db" => "The loudest the amp may go when the phone is at full volume. −6 dB is the listen-tested ceiling; above it the Amp2 clips and shuts down.",
    "interpolation" => "How shairport-sync stays in sync with the sender: auto picks soxr when the CPU allows, basic drops/duplicates frames, soxr resamples (best quality, more CPU).",
    "output_format" => "Sample format handed to the DAC. S32_LE is the HiFiBerry's native format; S16_LE is lighter on the CPU."
  }.freeze

  def initialize(settings:, schema:, groups:, flake:, updates:, error: nil, notice: nil, alert: nil, embedded: false)
    @settings = settings
    @schema = schema
    @groups = groups
    @flake = flake
    @updates = updates
    @error = error
    @notice = notice
    @alert = alert
    @embedded = embedded # inside the Settings overlay (Turbo Frame in a Sheet) vs. a full page
  end

  # The whole page is one Turbo Frame: the Sheet loads it. A fixed-height column: rigid title
  # bar, rigid stats bar, and only the middle scrolls (smoothly, contained).
  def view_template
    turbo_frame(id: "settings", class: "flex h-full min-h-0 flex-col") do
      header(class: "flex shrink-0 items-center gap-3 border-b bg-background px-6 py-4") do
        close_cross
        Heading(level: 1, size: "5") { "Settings" }
      end
      div(class: "min-h-0 flex-1 space-y-6 overflow-y-auto overscroll-none px-6 py-6 [-webkit-overflow-scrolling:touch]") do
        Alert(variant: :success) { AlertDescription { @notice } } if @notice.present?
        Alert(variant: :destructive) { AlertDescription { @alert } } if @alert.present?
        Alert(variant: :destructive) { AlertDescription { @error } } if @error

        airplay_card
        actions_card(@groups[0][:actions]) if @groups[0]
        sound_card
        actions_card(@groups[1][:actions]) if @groups[1]
        pre(id: "action-output", hidden: true,
            class: "max-h-72 overflow-auto rounded-lg border bg-muted/40 p-3 font-mono text-xs whitespace-pre-wrap")
      end
      footer(class: "shrink-0 border-t bg-background px-6 py-3") { stats }
    end
  end

  private

  # In the overlay: closes the Sheet. On the full page: back to the home screen.
  def close_cross
    attrs = { class: "-ml-2 grid h-8 w-8 place-items-center rounded-sm text-muted-foreground hover:text-foreground", aria_label: "Close settings" }
    if @embedded
      button(type: "button", data: { close_sheet: true, action: "click->ruby-ui--sheet-content#close" }, **attrs) { cross_icon }
    else
      a(href: root_path, **attrs) { cross_icon }
    end
  end

  def cross_icon
    svg(viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", stroke_width: "2", stroke_linecap: "round", class: "h-5 w-5", aria_hidden: "true") do |s|
      s.path(d: "M18 6 6 18M6 6l12 12")
    end
  end

  def card(title, &)
    Card do
      CardHeader { CardTitle { title } }
      CardContent(&)
    end
  end

  # ---- AirPlay: name (saves as you type), password (eye + "+"), version + update status --------

  def airplay_card
    card("AirPlay") do
      div(class: "space-y-5") do
        autosave_form(delay: 800) do
          field("settings[name]", "Name") do |id|
            Input(id: id, name: "settings[name]", value: @settings["name"], maxlength: 40, required: true, autocomplete: "off",
                  data: { action: "input->autosave#changed" })
          end
        end
        autosave_form(delay: 0) do
          field("settings[password]", "Password") do |id|
            div(class: "flex items-center gap-2", data: { controller: "reveal" }) do
              Input(id: id, type: :password, name: "settings[password]", value: @settings["password"], maxlength: 64,
                    autocomplete: "off", class: "flex-1", data: { reveal_target: "input" })
              Button(variant: :ghost, icon: true, type: :button, aria_label: "Show or hide the password", data: { action: "click->reveal#toggle" }) do
                eye_icon(on: true)
                eye_icon(on: false)
              end
              Button(**QUIET_BUTTON, icon: true, type: :button, aria_label: "Save the password", data: { action: "click->autosave#save" }) { "+" }
            end
          end
        end
        version_line
      end
    end
  end

  def eye_icon(on:)
    svg(viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", stroke_width: "2", stroke_linecap: "round", stroke_linejoin: "round",
        class: ["h-4 w-4", ("hidden" unless on)], data: { reveal_target: (on ? "on" : "off") }, aria_hidden: "true") do |s|
      s.path(d: "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7Z")
      s.circle(cx: "12", cy: "12", r: "3")
      s.path(d: "M3 3l18 18") unless on
    end
  end

  # "shairport-sync 5.5.2 · ✓ up to date · Check for updates" — the badge is rewritten in place
  # by updates_controller.js; the daily timer keeps the cached answer fresh on its own.
  def version_line
    base = "inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset"
    ok = "text-success bg-success/10 ring-success/20"
    warn = "text-warning bg-warning/10 ring-warning/20"
    text, tone =
      if @updates["error"] then ["✗ check failed", warn]
      elsif @updates["up_to_date"] then ["✓ up to date", ok]
      elsif @updates["latest"] then ["↑ #{@updates["latest"]} available", warn]
      else ["not checked yet", "text-muted-foreground bg-muted ring-border"]
      end
    div(class: "flex flex-wrap items-center gap-x-3 gap-y-1 pt-1 text-xs text-muted-foreground", data: { controller: "updates", updates_url_value: updates_check_path }) do
      span { "shairport-sync #{@updates["running"].presence || "?"}" }
      span(class: [base, tone], data: { updates_target: "badge", base: base, ok: ok, warn: warn }) { text }
      a(href: @updates["releases_url"] || "#", class: "underline underline-offset-4", data: { updates_target: "link", action: "click->updates#check" }) { "Check for updates" }
    end
  end

  # ---- Sound: saves 1 s after a change; selects right-aligned, one line each --------------------

  def sound_card
    card("Sound") do
      autosave_form(delay: 1000) do
        input(type: "hidden", name: "settings[volume_range_db]", value: @settings["volume_range_db"])
        row("Maximum volume (dB)", tip: TIPS["volume_max_db"]) do
          div(class: "flex items-center gap-2", data: { controller: "stepper" }) do
            Button(variant: :outline, icon: true, type: :button, aria_label: "Lower by 1 dB", data: { action: "click->stepper#down" }) { "−" }
            Input(id: "settings-volume_max_db", type: :number, name: "settings[volume_max_db]", value: @settings["volume_max_db"], min: -30, max: 0, step: 1,
                  inputmode: "numeric", title: TIPS["volume_max_db"], class: "w-24 text-center",
                  data: { stepper_target: "input", action: "input->autosave#changed" })
            Button(variant: :outline, icon: true, type: :button, aria_label: "Raise by 1 dB", data: { action: "click->stepper#up" }) { "+" }
          end
        end
        row("Resampling", tip: TIPS["interpolation"]) { select_field("settings-interpolation", "settings[interpolation]", @schema["interpolation"][:values], @settings["interpolation"], tip: TIPS["interpolation"]) }
        row("Output format", tip: TIPS["output_format"]) { select_field("settings-output_format", "settings[output_format]", @schema["output_format"][:values], @settings["output_format"], tip: TIPS["output_format"]) }
      end
    end
  end

  # A form that saves itself (autosave_controller.js); the status line replaces the Apply button.
  def autosave_form(delay:)
    Form(action: settings_path, method: "post", class: "space-y-4", data: { controller: "autosave", autosave_delay_value: delay, action: "submit->autosave#submit" }) do
      input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
      yield
      p(class: "min-h-4 text-xs text-muted-foreground", data: { autosave_target: "status" }, aria_live: "polite")
    end
  end

  def field(name, label)
    id = name.gsub(/\W+/, "-")
    FormField do
      FormFieldLabel(for: id) { label }
      yield id
      FormFieldError()
    end
  end

  # label left, control right, one line (wraps only if it must)
  def row(label, tip: nil)
    div(class: "flex flex-wrap items-center justify-between gap-x-4 gap-y-2") do
      FormFieldLabel(title: tip) { label }
      div(class: "ml-auto") { yield }
    end
  end

  def select_field(id, name, values, current, tip: nil)
    NativeSelect(id: id, name: name, title: tip, data: { action: "change->autosave#changed" }) do
      values.each { |v| NativeSelectOption(value: v, selected: (v == current)) { v } }
    end
  end

  # What is running: build number (commit count) and flake revision.
  def stats
    div(class: "font-mono text-xs [overflow-wrap:anywhere]") do
      span(class: "font-semibold") { "build #{@flake["build"].presence || "dev"}" }
      span(class: "text-muted-foreground") { " · #{@flake["version"].presence || "unknown"}" }
    end
  end

  # One card per group, no headings: Restart AirPlay alone, then Reboot + Redeploy together.
  def actions_card(actions)
    return if actions.empty?

    Card do
      CardContent(class: "pt-2 pb-2") do
        table(class: "w-full", data: { controller: "arm" }) do
          tbody { actions.each { |a| render Components::ActionRow.new(action: a) } }
        end
      end
    end
  end
end
