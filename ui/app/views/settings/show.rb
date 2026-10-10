# frozen_string_literal: true

# Settings, in this order: AirPlay (name and password save 1 s after the last keystroke; the
# password has an eye toggle; a saved name also renames the brand in the top bar),
# Restart AirPlay, Sound (saves 1 s after a change), Reboot + Redeploy (armed by "Yes" boxes).
# No Apply buttons, no help text (tooltips on the sound settings). No volume control here on
# purpose: the phone sets the level, `volume_max_db` is the ceiling.
class Views::Settings::Show < Views::Base
  include Phlex::Rails::Helpers::FormAuthenticityToken

  # Help for the sound settings: shown by the (?) next to each label (hover or tap, see help/1)
  # and as the title of every choice.
  TIPS = {
    "volume_max_db" => "The loudest the amp may go when the phone is at full volume, in dB below the DAC's maximum (0 dB). The phone's slider is mapped onto the range below this ceiling: 1 dB lower makes everything about 11 % quieter, 1 dB higher about 12 % louder. −6 dB is the listen-tested ceiling — above it the Amp2 clips and shuts down.",
    "interpolation" => "How shairport-sync keeps the stream in sync with the phone's clock when the two drift apart.\nauto — soxr when the Pi's CPU allows, basic otherwise (recommended).\nvernier — fine-grained frame insertion/deletion: cheap, less audible than basic.\nsoxr — real resampling, the best quality, the most CPU.\nbasic — drop or repeat single frames: the cheapest, occasionally audible.",
    "interpolation:auto" => "soxr when the CPU allows, basic otherwise (recommended)",
    "interpolation:vernier" => "fine-grained frame insertion/deletion: cheap, less audible than basic",
    "interpolation:soxr" => "real resampling: the best quality, the most CPU",
    "interpolation:basic" => "drop or repeat single frames: the cheapest, occasionally audible",
    "output_format" => "The sample format handed to the DAC.\nS32_LE — 32-bit, the HiFiBerry's native format: the volume is applied with more headroom (recommended).\nS16_LE — 16-bit: lighter on the CPU, a little less precise at low volume.",
    "output_format:S32_LE" => "32-bit, the HiFiBerry's native format: more headroom for the volume (recommended)",
    "output_format:S16_LE" => "16-bit: lighter on the CPU, a little less precise at low volume"
  }.freeze

  def initialize(settings:, schema:, groups:, flake:, updates:, mac: nil, network: {}, error: nil, notice: nil, alert: nil, embedded: false)
    @settings = settings
    @schema = schema
    @groups = groups
    @flake = flake
    @updates = updates
    @mac = mac
    @network = network
    @error = error
    @notice = notice
    @alert = alert
    @embedded = embedded # inside the Settings overlay (Turbo Frame in a Sheet) vs. a full page
  end

  # The whole page is one Turbo Frame: the Sheet loads it. A fixed-height column: no title bar
  # (the pane hangs under the top bar, which says "Settings" already), a rigid stats bar at the
  # bottom, and only the part above it scrolls (smoothly, contained).
  def view_template
    turbo_frame(id: "settings", class: "flex h-full min-h-0 flex-col") do
      div(class: "min-h-0 flex-1 space-y-6 overflow-y-auto overscroll-none px-6 py-6 [-webkit-overflow-scrolling:touch]") do
        Alert(variant: :success) { AlertDescription { @notice } } if @notice.present?
        Alert(variant: :destructive) { AlertDescription { @alert } } if @alert.present?
        Alert(variant: :destructive) { AlertDescription { @error } } if @error

        airplay_card
        actions_card(@groups[0][:actions]) if @groups[0]
        sound_card
        network_card
        actions_card(@groups[1][:actions]) if @groups[1]
        pre(id: "action-output", hidden: true,
            class: "max-h-72 overflow-auto rounded-lg border bg-muted/40 p-3 font-mono text-xs whitespace-pre-wrap")
      end
      # a little more room at the bottom: the rounded corners / home indicator of a phone
      footer(class: "shrink-0 border-t bg-background px-6 pt-3 pb-[max(1.25rem,env(safe-area-inset-bottom))]") { stats }
    end
  end

  private

  def card(title, &)
    Card do
      CardHeader { CardTitle { title } }
      CardContent(&)
    end
  end

  # ---- AirPlay: name and password (save 1 s after typing), version + update status -------------

  def airplay_card
    card("AirPlay") do
      div(class: "space-y-5") do
        autosave_form(delay: 1000) do
          field("settings[name]", "Name") do |id|
            Input(id: id, name: "settings[name]", value: @settings["name"], maxlength: 40, required: true, autocomplete: "off",
                  data: { action: "input->autosave#changed" })
          end
        end
        autosave_form(delay: 1000) do
          field("settings[password]", "Password") do |id|
            div(class: "flex items-center gap-2", data: { controller: "reveal" }) do
              Input(id: id, type: :password, name: "settings[password]", value: @settings["password"], maxlength: 64,
                    autocomplete: "off", class: "flex-1", data: { reveal_target: "input", action: "input->autosave#changed" })
              Button(variant: :ghost, icon: true, type: :button, aria_label: "Show or hide the password", data: { action: "click->reveal#toggle" }) do
                eye_icon(on: true)
                eye_icon(on: false)
              end
            end
          end
        end
        # the box's hardware address (how the phone's AirPlay list tells receivers apart)
        p(class: "font-mono text-xs text-muted-foreground") { "MAC: #{@mac}" } if @mac
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
  # The update badge (the small tinted pill): green "✓ up to date", red "↑ 5.6.0 available" (or
  # "✗ check failed"), grey when never checked. Hovering turns it grey and offers the action
  # ("Check now" / "Update now") — the two labels share one grid cell, so the pill keeps its
  # width; a tap runs it with a spinner ("Checking…" / "Updating…"). updates_controller.js
  # drives it: check = POST /updates/check; update = the update-shairport action (builds the
  # release on top of the flake, switches, audio stops for the switch — no confirmation), then
  # polls /updates/status until the job is done.
  UPDATE_BUTTON = "group inline-flex cursor-pointer items-center gap-1.5 rounded-md px-2 py-0.5 text-xs font-medium ring-1 ring-inset transition-colors disabled:cursor-default"
  UPDATE_TONES = {
    "ok" => "text-success bg-success/10 ring-success/20 hover:text-muted-foreground hover:bg-muted hover:ring-border",
    "available" => "text-destructive bg-destructive/10 ring-destructive/20 hover:text-muted-foreground hover:bg-muted hover:ring-border",
    "error" => "text-destructive bg-destructive/10 ring-destructive/20 hover:text-muted-foreground hover:bg-muted hover:ring-border",
    "unknown" => "text-muted-foreground bg-muted ring-border hover:text-foreground",
    "busy" => "text-muted-foreground bg-muted ring-border"
  }.freeze
  UPDATE_LABELS = { # state => [at rest, on hover]
    "ok" => ["✓ up to date", "Check now"],
    "available" => ["↑ %s available", "Update now"],
    "error" => ["✗ check failed", "Check now"],
    "unknown" => ["Check for updates", "Check now"]
  }.freeze

  def version_line
    state =
      if @updates["error"] then "error"
      elsif @updates["up_to_date"] then "ok"
      elsif @updates["latest"] then "available"
      else "unknown"
      end
    rest, hover = UPDATE_LABELS[state]
    div(class: "flex flex-wrap items-center gap-x-3 gap-y-2 pt-1 text-xs text-muted-foreground",
        data: { controller: "updates", updates_check_url_value: updates_check_path, updates_status_url_value: updates_status_path,
                updates_apply_url_value: "#{api_actions_path}/update-shairport", updates_state_value: state,
                updates_latest_value: @updates["latest"].to_s, updates_tones_value: UPDATE_TONES.to_json, updates_labels_value: UPDATE_LABELS.to_json }) do
      span { "shairport-sync #{@updates["running"].presence || "?"}" }
      button(type: "button", class: [UPDATE_BUTTON, UPDATE_TONES[state]], title: @updates["error"].to_s,
             data: { updates_target: "button", base: UPDATE_BUTTON, action: "click->updates#tap" }) do
        svg(class: "hidden h-3.5 w-3.5 animate-spin", viewBox: "0 0 24 24", fill: "none", aria_hidden: "true", data: { updates_target: "spinner" }) do |s|
          s.circle(cx: "12", cy: "12", r: "10", stroke: "currentColor", stroke_width: "3", class: "opacity-25")
          s.path(d: "M22 12a10 10 0 0 1-10 10", stroke: "currentColor", stroke_width: "3", stroke_linecap: "round")
        end
        span(class: "inline-grid text-center") do # both labels in one cell: the pill is as wide as the longer one
          span(class: "col-start-1 row-start-1 group-hover:invisible", data: { updates_target: "rest" }) { rest.sub("%s", @updates["latest"].to_s) }
          span(class: "invisible col-start-1 row-start-1 group-hover:visible", data: { updates_target: "hover" }) { hover }
        end
      end
    end
  end

  # ---- Sound: saves 1 s after a change; selects right-aligned, one line each --------------------

  def sound_card
    card("Sound") do
      autosave_form(delay: 1000) do
        input(type: "hidden", name: "settings[volume_range_db]", value: @settings["volume_range_db"])
        row("Maximum volume (dB)", tip: TIPS["volume_max_db"]) do
          # the number field's own stepper (min/max/step), nothing else
          Input(id: "settings-volume_max_db", type: :number, name: "settings[volume_max_db]", value: @settings["volume_max_db"], min: -30, max: 0, step: 1,
                inputmode: "numeric", class: "w-24 text-center", data: { action: "input->autosave#changed" })
        end
        row("Resampling", tip: TIPS["interpolation"]) { select_field("settings-interpolation", "settings[interpolation]", @schema["interpolation"][:values], @settings["interpolation"], key: "interpolation") }
        row("Output format", tip: TIPS["output_format"]) { select_field("settings-output_format", "settings[output_format]", @schema["output_format"][:values], @settings["output_format"], key: "output_format") }
      end
    end
  end

  # ---- Network: Wi‑Fi and Ethernet, status + leased address + a switch each; join a Wi‑Fi -------
  # The switch is only usable when switching off would not lock the user out (the other
  # interface is connected). network_controller.js posts network-set / wifi-connect and reloads
  # the frame. Nothing is shown when the status could not be read (the Mac preview).

  def network_card
    return if @network.empty?

    card("Network") do
      div(class: "space-y-5", data: { controller: "network", network_set_url_value: "#{api_actions_path}/network-set",
                                      network_connect_url_value: "#{api_actions_path}/wifi-connect" }) do
        @network.each_value { |s| network_row(s) }
        wifi_form
        p(class: "min-h-4 text-xs text-muted-foreground", data: { network_target: "status" }, aria_live: "polite")
      end
    end
  end

  def network_row(s)
    word = AirPlayOS::Network.describe(s)
    locked = s["enabled"] && !AirPlayOS::Network.may_disable?(@network, s["iface"])
    div(class: "flex items-center justify-between gap-4") do
      div(class: "min-w-0") do
        div(class: "flex items-center gap-2") do
          span(class: "text-sm font-medium") { s["label"] }
          span(class: ["text-xs", (s["connected"] ? "text-success" : "text-muted-foreground")]) { word }
        end
        # the leased address, small; the Wi‑Fi line names the network too
        p(class: "truncate font-mono text-xs text-muted-foreground") do
          plain(s["ip4"] ? s["ip4"].sub(%r{/\d+\z}, "") : "no address")
          plain(" · #{s["ssid"]}") if s["ssid"].present? && s["connected"]
        end
      end
      Switch(include_hidden: false, checked: s["enabled"], disabled: (locked || !s["present"]),
             aria_label: "#{s["label"]} on or off",
             title: (locked ? "The only connected interface — connect the other one before switching this off" : nil),
             data: { iface: s["iface"], action: "change->network#toggle" })
    end
  end

  # Join (or re-key) a Wi‑Fi network from here: name + password, then Connect. The receiver
  # moves to that network; if it is another one, reach it at its new address.
  def wifi_form
    wifi = @network["wlan0"] || {}
    Form(action: "#", method: "post", class: "space-y-3 border-t pt-4", data: { action: "submit->network#connect" }) do
      field("wifi[ssid]", "Wi‑Fi network") do |id|
        Input(id: id, name: "ssid", value: wifi["ssid"], maxlength: 32, autocomplete: "off", data: { network_target: "ssid" })
      end
      field("wifi[psk]", "Wi‑Fi password") do |id|
        div(class: "flex items-center gap-2", data: { controller: "reveal" }) do
          Input(id: id, type: :password, name: "psk", maxlength: 64, autocomplete: "off", class: "flex-1", data: { reveal_target: "input", network_target: "psk" })
          Button(variant: :ghost, icon: true, type: :button, aria_label: "Show or hide the password", data: { action: "click->reveal#toggle" }) do
            eye_icon(on: true)
            eye_icon(on: false)
          end
          Button(**QUIET_BUTTON, type: :submit) { "Connect" }
        end
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
    div(class: "relative flex flex-wrap items-center justify-between gap-x-4 gap-y-2") do
      div(class: "flex items-center gap-1.5") do
        FormFieldLabel { label }
        help(tip) if tip
      end
      div(class: "ml-auto") { yield }
    end
  end

  # A small (?) that shows its help on hover, and on focus (a tap on the phone): CSS only,
  # no JavaScript, no library. The popover is positioned against the row (relative), under
  # it and from its left edge, never wider than the row — so it stays inside the pane.
  def help(text)
    span(class: "group/help inline-flex") do
      button(type: "button", aria_label: "Help", class: "grid h-4 w-4 cursor-help place-items-center rounded-full border text-[10px] font-semibold leading-none text-muted-foreground hover:text-foreground focus:outline-none focus-visible:ring-2 focus-visible:ring-ring") { "?" }
      span(role: "tooltip",
           class: "invisible absolute left-0 top-full z-20 mt-1 w-72 max-w-full whitespace-pre-line rounded-md border bg-popover px-3 py-2 text-xs leading-snug text-popover-foreground shadow-md group-hover/help:visible group-focus-within/help:visible") { text }
    end
  end

  # The select carries the full description of the choices; each option its own one-liner.
  def select_field(id, name, values, current, key:)
    NativeSelect(id: id, name: name, title: TIPS[key], data: { action: "change->autosave#changed" }) do
      values.each { |v| NativeSelectOption(value: v, selected: (v == current), title: TIPS["#{key}:#{v}"]) { v } }
    end
  end

  # What is running: the version (v + build number = the commit count, which is what the vN tags
  # are cut from; "dev" for a dirty tree) over the flake source in the Nix store
  # (/opt/airplay-os → /nix/store/…-source).
  def stats
    div(class: "font-mono text-xs [overflow-wrap:anywhere]") do
      p(class: "font-semibold") { @flake["build"].present? && @flake["build"] != "dev" ? "v#{@flake["build"]}" : "dev" }
      p(class: "text-muted-foreground") { @flake["path"].presence || @flake["version"].presence || "unknown" }
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
