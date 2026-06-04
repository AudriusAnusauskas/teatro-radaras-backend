class Api::DirectorsController < Api::BaseController
    def index
      directors = Director.includes(productions: :theater)
      directors = apply_filters(directors, params)
  
      render json: {
        directors: directors.map { |d| DirectorSerializer.list(d) },
        count: directors.size
      }
    end
  
    def show
      director = Director.includes(productions: [:theater, :screenings, :reviews, :user_ratings])
                         .friendly.find(params[:slug])
  
      render json: { director: DirectorSerializer.detail(director) }
    end
  
    private
  
    def apply_filters(scope, _params)
      scope
    end
  end
