# frozen_string_literal: true

class Components::Base < Phlex::HTML
  include RubyUI
  # Include any helpers you want to be available across all components
  include Phlex::Rails::Helpers::Routes

  # Turbo Frames: Settings loads into one inside the Sheet and submits in place.
  register_element :turbo_frame, tag: "turbo-frame"

  # The selected tab: no underline, a very subtle glow.
  TAB = "no-underline text-sm"
  TAB_ACTIVE = "text-foreground font-semibold [text-shadow:0_0_10px_color-mix(in_srgb,currentColor_45%,transparent)]"
  TAB_IDLE = "text-muted-foreground"
  # the quiet action buttons (Apply, Restart): stock secondary, a notch darker in light mode only
  SOFT_BUTTON = "bg-zinc-200 hover:bg-zinc-300 dark:bg-secondary dark:hover:bg-secondary/80"

  if Rails.env.development?
    def before_template
      comment { "Before #{self.class.name}" }
      super
    end
  end
end
