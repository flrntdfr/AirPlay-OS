# frozen_string_literal: true

module RubyUI
  # AirPlay OS: the pane hangs under the fixed top bar (top-12) and so does the dimmed backdrop,
  # so the bar itself is never dimmed and stays usable; no close button (click/tap anywhere
  # outside the pane closes it — sheet_content_controller.js), no blur, no slide/fade animation:
  # it appears and disappears at once.
  class SheetContent < Base
    SIDE_CLASS = {
      top: "inset-x-0 top-12 border-b",
      right: "top-12 bottom-0 right-0 border-l",
      bottom: "inset-x-0 bottom-0 border-t",
      left: "top-12 bottom-0 left-0 border-r"
    }

    def initialize(side: :right, **attrs)
      @side = side
      @side_classes = SIDE_CLASS[side]
      super(**attrs)
    end

    def view_template(&block)
      template(data: {ruby_ui__sheet_target: "content"}) do
        div(data: {controller: "ruby-ui--sheet-content"}) do
          backdrop
          div(**attrs) do
            block&.call
          end
        end
      end
    end

    private

    def default_attrs
      {
        data_state: "open",
        class: [
          "fixed pointer-events-auto z-20 gap-4 bg-background p-6 shadow-lg overflow-scroll",
          @side_classes
        ]
      }
    end

    def backdrop
      div(
        data_state: "open",
        data_action: "click->ruby-ui--sheet-content#close",
        class:
              "fixed pointer-events-auto inset-x-0 top-12 bottom-0 z-20 cursor-pointer bg-background/80"
      )
    end
  end
end
