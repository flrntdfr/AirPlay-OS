# frozen_string_literal: true

# One allow-listed control action as a table row: label | arming checkbox | button. A table keeps
# the checkboxes and the buttons of a card in straight columns. Actions flagged `confirm` are
# armed by an "Ok" checkbox (Stimulus `arm` controller keeps the button disabled until ticked).
# The request itself is made by actions.js from the button carrying data-action-id
# (POST /api/actions/<id>).
class Components::ActionRow < Components::Base
  def initialize(action:)
    @a = action
  end

  def view_template
    tr(class: "border-b last:border-0", data: ({ controller: "arm" } if @a["confirm"])) do
      td(class: "py-4 pr-4 text-sm font-medium") { @a["label"] }
      td(class: "w-px whitespace-nowrap py-4 pr-4") { arm_box if @a["confirm"] }
      td(class: "w-px py-4 text-right") { button }
    end
  end

  private

  def variant = @a["danger"] ? :destructive : :outline

  # "Restart AirPlay" → "Restart", "Redeploy" stays "Redeploy"
  def verb = @a["label"].to_s.split(" ").first || "Run"

  def arm_box
    id = "arm-#{@a["id"]}"
    label(for: id, class: "flex cursor-pointer select-none items-center gap-2 text-sm") do
      Checkbox(id: id, data: { arm_target: "box", action: "change->arm#toggle" })
      span { "Ok" }
    end
  end

  def button
    attrs = { variant: variant, size: :sm, data: { action_id: @a["id"] } }
    attrs.merge!(variant: :secondary, class: SOFT_BUTTON) unless @a["confirm"] || @a["danger"] # plain actions look like Apply
    if @a["confirm"]
      attrs[:disabled] = true
      attrs[:data][:arm_target] = "button"
    end
    Button(**attrs) { verb }
  end
end
