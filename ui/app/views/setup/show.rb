# frozen_string_literal: true

# Wi‑Fi onboarding. Not in the navigation: phones land here through the setup hotspot's captive
# portal (dnsmasq answers every name with 10.42.0.1).
class Views::Setup::Show < Views::Base
  include Phlex::Rails::Helpers::FormAuthenticityToken

  def initialize(status:, networks:, error: nil)
    @status = status
    @networks = networks
    @error = error
  end

  def view_template
    div(class: "space-y-6 pt-6") do
      Heading(level: 1, size: "6") { "Wi‑Fi" }
      Alert(variant: :destructive) { AlertDescription { @error } } if @error

      Card() do
        CardHeader do
          CardTitle { "Network" }
          CardDescription { status_text }
        end
        CardContent(class: "space-y-5") do
          form(action: setup_scan_path, method: "post") do
            input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
            Button(type: :submit, variant: :outline) { "Scan for networks" }
          end
          join_form if @networks.any?
        end
      end
    end
  end

  private

  def status_text
    if @status["hotspot"] then "Setup hotspot active — pick your home network below."
    elsif @status["wifi_connected"] then "Connected to #{@status["connection"]} (#{@status["ip4"]})."
    else "Not connected (#{@status["wifi_state"]})."
    end
  end

  def join_form
    Form(action: setup_connect_path, method: "post", class: "space-y-5") do
      input(type: "hidden", name: "authenticity_token", value: form_authenticity_token)
      FormField do
        FormFieldLabel(for: "ssid") { "Network" }
        NativeSelect(id: "ssid", name: "ssid", required: true, class: "w-full") do
          @networks.each do |n|
            tags = [n["signal"] && "#{n["signal"]}%", (n["open"] ? "open" : nil), (n["in_use"] ? "current" : nil)].compact
            NativeSelectOption(value: n["ssid"]) { [n["ssid"], *tags].join(" · ") }
          end
        end
      end
      FormField do
        FormFieldLabel(for: "psk") { "Passphrase" }
        Input(id: "psk", type: :password, name: "psk", minlength: 8, maxlength: 63, autocomplete: "off")
        FormFieldHint { "Leave empty for an open network." }
      end
      div(class: "flex items-center gap-3") do
        Button(type: :submit) { "Join" }
        span(class: "text-xs text-muted-foreground") { "the hotspot drops while Ampberry joins; reconnect your phone afterwards" }
      end
    end
  end
end
