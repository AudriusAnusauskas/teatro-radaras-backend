class Api::ProductionsController < Api::BaseController
    def index
      productions = Production.includes(:theater, :director, :screenings, :reviews)
      productions = apply_filters(productions, params)
  
      render json: {
        productions: productions.map { |p| ProductionSerializer.list(p) },
        count: productions.size
      }
    end
  
    def show
      production = Production.includes(:theater, :director, :screenings, :reviews)
                             .friendly.find(params[:slug])
  
      render json: { production: ProductionSerializer.detail(production) }
    end
  
    private
  
    def apply_filters(scope, params)
      scope = scope.by_city(params[:city])                 if params[:city].present?
      scope = scope.joins(:theater)
                   .where(theaters: { slug: params[:theater_slug] }) if params[:theater_slug].present?
      scope = scope.by_genre(params[:genre])               if params[:genre].present?
      scope = scope.where(premiere_date: 1.year.ago..)     if params[:premiere_only] == "true"
  
      if params[:min_rating].present?
        min = params[:min_rating].to_f
        qualified_ids = Review.matched
                              .where.not(rating: nil)
                              .group(:production_id)
                              .having("AVG(rating) >= ?", min)
                              .pluck(:production_id)
        scope = scope.where(id: qualified_ids)
      end
  
      scope
    end
  end
