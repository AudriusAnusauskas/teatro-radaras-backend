class Api::ReviewsController < Api::BaseController
    def index
      reviews = Review.matched.recent.includes(production: [:theater, :director])
      reviews = apply_filters(reviews, params)
  
      render json: {
        reviews: reviews.map { |r| ReviewSerializer.list(r) },
        count: reviews.size
      }
    end
  
    private
  
    def apply_filters(scope, params)
      scope = scope.where(publication: params[:publication]) if params[:publication].present?

      if params[:production_slug].present?
        scope = scope.joins(production: :theater)
                     .where(productions: { slug: params[:production_slug] })
        scope = scope.where(theaters: { slug: params[:theater_slug] }) if params[:theater_slug].present?
      elsif params[:theater_slug].present?
        scope = scope.joins(production: :theater)
                     .where(theaters: { slug: params[:theater_slug] })
      end

      scope = scope.by_year(params[:year].to_i) if params[:year].present?

      scope
    end
  end
