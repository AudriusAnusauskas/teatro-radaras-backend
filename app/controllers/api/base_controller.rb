class Api::BaseController < ActionController::API
    rescue_from ActiveRecord::RecordNotFound do |e|
      render json: { error: "not_found", message: e.message }, status: :not_found
    end
  end