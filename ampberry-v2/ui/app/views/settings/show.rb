# frozen_string_literal: true

# Settings: the AirPlay receiver settings (one card), then the control actions grouped —
# Maintenance first, System last. No volume control here on purpose: the phone sets the level,
# `volume_max_db` is the ceiling. No help text: labels only.
class Views::Settings::Show < Views::Base
  include Phlex::Rails::Helpers::FormAuthenticityToken

  def initialize(settings:, schema:, groups:, flake:, error: nil, notice: nil, alert: nil, embedded: false)
    @settings = settings
    @schema = schema
    @groups = groups
    @flake = flake
    @error = error
    @notice = notice
    @alert = alert
    @embedded = embedded # inside the Settings overlay (Turbo Frame in a Sheet) vs. a full page
  end

  # The whole page is one Turbo Frame: the Sheet loads it, the form re-renders it in place.
  # A fixed-height column: rigid title bar, rigid stats bar, and only the middle scrolls (smoothly,
  # contained — nothing bounces the bars).
  def view_template
    turbo_frame(id: "settings", class: "flex h-full min-h-0 flex-col") do
      header(class: "flex shrink-0 items-center gap-3 border-b bg-background px-6 py-4") do
        close_cross
        Heading(level: 1, size: "5") { "Settings" }
      end
      div(class: "min-h-0 flex-1 space-y-6 overflow-y-auto overscroll-contain px-6 py-6 [-webkit-overflow-scrolling:touch]") do
        Alert(variant: :success) { AlertDescription { @notice } } if @notice.present?
        Alert(variant: :destructive) { AlertDescription { @alert } } if @alert.present?
        Alert(variant: :destructive) { AlertDescription { @error } } if @error

        airplay_card
        sound_card
        @groups.each { |g| actions_card(g[:actions]) }
        pre(id: "action-output", hidden: true,
            class: "max-h-72 overflow-auto rounded-lg border bg-muted/40 p-3 font-mono text-xs whitespace-pre-wrap")
      end
      footer(class: "shrink-0 border-t bg-background px-6 py-3") { stats }
    end
  end

  private

  # In the overlay: closes the Sheet (Stimulus action on the sheet-content controller around the
  # frame). On the full page: back to the home screen.
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

  def airplay_card
    card("AirPlay") do
      settings_form do
        field("settings[name]", "Name") do |id|
          Input(id: id, name: "settings[name]", value: @settings["name"], maxlength: 40, required: true, autocomplete: "off")
        end
        field("settings[password]", "Password") do |id|
          Input(id: id, name: "settings[password]", value: @settings["password"], maxlength: 64, autocomplete: "off")
        end
      end
    end
  end

  def sound_card
    card("Sound") do
      settings_form do
        input(type: "hidden", name: "settings[volume_range_db]", value: @settings["volume_range_db"])
        field("settings[volume_max_db]", "Maximum volume (dB)") do |id|
          div(class: "flex items-center gap-2", data: { controller: "stepper" }) do
            Button(variant: :outline, icon: true, type: :button, aria_label: "Lower by 1 dB", data: { action: "click->stepper#down" }) { "−" }
            Input(id: id, type: :number, name: "settings[volume_max_db]", value: @settings["volume_max_db"], min: -30, max: 0, step: 1,
                  inputmode: "numeric", class: "w-24 text-center", data: { stepper_target: "input" })
            Button(variant: :outline, icon: true, type: :button, aria_label: "Raise by 1 dB", data: { action: "click->stepper#up" }) { "+" }
          end
        end
        field("settings[interpolation]", "Resampling") do |id|
          select_field(id, "settings[interpolation]", @schema["interpolation"][:values], @settings["interpolation"])
        end
        field("settings[output_format]", "Output format") do |id|
          select_field(id, "settings[output_format]", @schema["output_format"][:values], @settings["output_format"])
        end
      end
    end
  end

  # Each card is its own form: settings-apply merges what it receives into the current settings.
  def settings_form
    Form(action: settings_path, method: "post", class: "space-y-5") do
      input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
      yield
      div(class: "pt-1") { Button(type: :submit, variant: :secondary, class: SOFT_BUTTON) { "Apply" } }
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

  def select_field(id, name, values, current)
    NativeSelect(id: id, name: name, class: "w-full") do
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
