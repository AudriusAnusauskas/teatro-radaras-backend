class Api::RatingsController < Api::BaseController
    def create
      production = find_production_by_slug(
        params[:production_slug],
        theater_slug: params[:theater_slug]
      )
      rating = UserRating.find_or_initialize_by(production_id: production.id, **rating_identifier)
      rating.rating = params[:rating]
  
      if rating.save
        render json: serialize_response(rating, production), status: :created
      else
        render json: { errors: rating.errors.full_messages }, status: :unprocessable_entity
      end
    end
  
    private
  
    def rating_identifier
      return { user_id: current_user.id } if user_signed_in?
  
      session[:anon_id] ||= SecureRandom.uuid
      { session_id: session[:anon_id] }
    end
  
    def serialize_response(rating, production)
      {
        rating: {
          value: rating.rating
        },
        production: {
          slug: production.slug,
          audience_score: production.audience_score,
          audience_count: production.audience_count
        }
      }
    end
  end
