# frozen_string_literal: true

# One allow-listed control action as a table row: label | arming checkbox | button. A table keeps
# the checkboxes and the buttons of a card in straight columns. Actions flagged `confirm` are
# armed by an "Ok" checkbox; the `arm` controller on the table chains the confirm rows (the first
# Ok enables the next row's Ok) and their buttons read "Now".
# The request itself is made by actions.js from the button carrying data-action-id
# (POST /api/actions/<id>).
class Components::ActionRow < Components::Base
  def initialize(action:)
    @a = action
  end

  def view_template
    tr(class: "border-b last:border-0") do
      td(class: "py-4 pr-4 text-sm font-medium") { @a["label"] }
      td(class: "w-px whitespace-nowrap py-4 pr-4") { arm_box if @a["confirm"] }
      td(class: "w-px py-4 text-right") { button }
    end
  end

  private

  def variant = @a["danger"] ? :destructive : :outline

  # armed actions read "Now"; plain ones use the first word: "Restart AirPlay" → "Restart"
  def verb = @a["confirm"] ? "Now" : (@a["label"].to_s.split(" ").first || "Run")

  def arm_box
    id = "arm-#{@a["id"]}"
    label(for: id, class: "flex cursor-pointer select-none items-center gap-2 text-sm") do
      Checkbox(id: id, data: { arm_target: "box", action: "change->arm#toggle" })
      span { "Yes" }
    end
  end

  def button
    attrs = { variant: variant, size: :sm, data: { action_id: @a["id"] } }
    attrs.merge!(QUIET_BUTTON) unless @a["confirm"] || @a["danger"] # plain actions (Restart) look like Apply
    if @a["confirm"]
      attrs[:disabled] = true
      attrs[:data][:arm_target] = "button"
    end
    Button(**attrs) { verb }
  end
end
