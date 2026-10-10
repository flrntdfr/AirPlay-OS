# frozen_string_literal: true

# Rails flash → shadcn Alert (success / destructive), rendered above the page content.
class Components::Flash < Components::Base
  def initialize(notice: nil, alert: nil)
    @notice = notice
    @alert = alert
  end

  def view_template
    return if @notice.blank? && @alert.blank?

    div(class: "mx-auto w-full max-w-2xl px-4 pt-4") do
      Alert(variant: :success) { AlertDescription { @notice } } if @notice.present?
      Alert(variant: :destructive) { AlertDescription { @alert } } if @alert.present?
    end
  end
end
