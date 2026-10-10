# frozen_string_literal: true

class ApplicationController < ActionController::Base
  protect_from_forgery with: :exception
  helper_method :release

  def release = @release ||= AmpberryBridge.release
end
