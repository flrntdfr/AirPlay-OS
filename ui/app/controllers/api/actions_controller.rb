# frozen_string_literal: true

module Api
  # The control API over HTTP: GET /api/actions lists the allow-list, POST /api/actions/:id runs
  # one. Parameters go to the root side as JSON and are validated there against the declared
  # schema of the action; custom (config-file) actions accept none.
  class ActionsController < ActionController::API
    def index
      render json: { "actions" => AmpberryBridge.actions }
    end

    def create
      params_hash = request.request_parameters.fetch("params", {})
      params_hash = params_hash.to_unsafe_h if params_hash.respond_to?(:to_unsafe_h)
      res = AmpberryBridge.call(params[:id], params_hash)
      render json: res, status: res["ok"] ? :ok : :unprocessable_entity
    end
  end
end
