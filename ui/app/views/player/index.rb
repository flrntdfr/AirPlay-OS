# frozen_string_literal: true

# Home: the live log is the page (body.player makes the backdrop the page, scrollable — see
# app/assets/tailwind/application.css) and the player lives in the top bar (Components::Nav,
# driven by player.js). Nothing else to render here.
class Views::Player::Index < Views::Base
  def initialize(now:, release:)
    @now = now
    @release = release
  end

  def view_template; end
end
