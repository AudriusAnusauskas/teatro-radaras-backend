class Api::SessionsController < Api::BaseController
    def show
      if user_signed_in?
        render json: { user: serialize_user(current_user) }
      else
        render json: { user: nil }
      end
    end
  
    private
  
    def serialize_user(user)
      {
        id:         user.id,
        email:      user.email,
        name:       user.name,
        avatar_url: user.avatar_url,
        role:       user.role
      }
    end
  end
  