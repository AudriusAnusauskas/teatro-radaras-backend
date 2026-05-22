class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
    skip_before_action :verify_authenticity_token
  
    def google_oauth2
      user = User.from_google_omniauth(request.env["omniauth.auth"])
      sign_in user
      redirect_to ENV.fetch("FRONTEND_URL", "http://localhost:3000"), allow_other_host: true
    rescue StandardError => e
      Rails.logger.error("OAuth failure: #{e.message}")
      redirect_to "#{ENV.fetch('FRONTEND_URL')}/login?error=oauth_failed", allow_other_host: true
    end
  
    def failure
      redirect_to "#{ENV.fetch('FRONTEND_URL')}/login?error=oauth_cancelled", allow_other_host: true
    end
  end
  