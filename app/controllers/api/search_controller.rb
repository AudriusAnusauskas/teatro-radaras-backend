class Api::SearchController < Api::BaseController
    def index
      query = params[:q].to_s.strip
  
      productions = search_productions(query)
      theaters = search_theaters(query)
      directors = search_directors(query)
  
      render json: {
        productions: productions.map { |p| serialize_production(p) },
        theaters: theaters.map { |t| serialize_theater(t) },
        directors: directors.map { |d| serialize_director(d) },
        total: productions.size + theaters.size + directors.size
      }
    end
  
    private
  
    def search_productions(query)
      return Production.none if query.blank?
  
      Production.includes(:theater)
                .where("productions.title ILIKE ?", "%#{Production.sanitize_sql_like(query)}%")
                .limit(10)
    end
  
    def search_theaters(query)
      return Theater.none if query.blank?
  
      Theater.where("theaters.name ILIKE ?", "%#{Theater.sanitize_sql_like(query)}%")
             .limit(10)
    end
  
    def search_directors(query)
      return Director.none if query.blank?
  
      Director.where("directors.name ILIKE ?", "%#{Director.sanitize_sql_like(query)}%")
              .limit(10)
    end
  
    def serialize_production(production)
      {
        slug: production.slug,
        title: production.title,
        theater_short_name: production.theater.short_name
      }
    end
  
    def serialize_theater(theater)
      {
        slug: theater.slug,
        name: theater.name,
        city: theater.city
      }
    end
  
    def serialize_director(director)
      {
        slug: director.slug,
        name: director.name
      }
    end
  end
