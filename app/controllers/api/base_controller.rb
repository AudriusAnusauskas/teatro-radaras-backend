class Api::BaseController < ActionController::API
    include Devise::Controllers::Helpers

    rescue_from ActiveRecord::RecordNotFound do |e|
      render json: { error: "not_found", message: e.message }, status: :not_found
    end

    private

    def authenticate_user!
      return if user_signed_in?

      render json: { error: "unauthorized" }, status: :unauthorized
    end
  end