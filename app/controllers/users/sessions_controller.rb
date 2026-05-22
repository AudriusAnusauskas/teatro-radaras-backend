class Users::SessionsController < Devise::SessionsController
    skip_before_action :verify_authenticity_token
  
    def destroy
      sign_out current_user if current_user
      head :no_content
    end
  end
  