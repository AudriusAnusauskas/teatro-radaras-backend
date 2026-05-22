class Api::TheatersController < Api::BaseController
    def index
      theaters = Theater.includes(:productions)
      theaters = apply_filters(theaters, params)
  
      render json: {
        theaters: theaters.map { |t| TheaterSerializer.list(t) },
        count: theaters.size
      }
    end
  
    def show
      theater = Theater.includes(productions: [:director, :screenings, :reviews])
                       .friendly.find(params[:slug])
  
      render json: { theater: TheaterSerializer.detail(theater) }
    end
  
    private
  
    def apply_filters(scope, params)
      scope = scope.by_city(params[:city]) if params[:city].present?
  
      scope
    end
  end
