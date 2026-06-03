class Api::HomeController < Api::BaseController
  # Hardcoded display order for the homepage city breakdown.
  CITY_ORDER = ["Vilnius", "Kaunas", "Klaipėda", "Panevėžys", "Šiauliai"].freeze

  # GET /api/home/top_rated
  # Top 6 productions by average radaras_score across their matched reviews.
  def top_rated
    # Step 1: aggregate to find the top production IDs. Kept as a clean
    # GROUP BY productions.id with no eager-loaded joins so Postgres doesn't
    # demand the joined tables' columns in the GROUP BY clause.
    top_ids = Production.active
                        .joins(:reviews)
                        .merge(Review.matched)
                        .where.not(reviews: { radaras_score: nil })
                        .group("productions.id")
                        .order(Arel.sql("AVG(reviews.radaras_score) DESC"))
                        .limit(6)
                        .pluck("productions.id")

    # Step 2: load full records with associations, restoring the ranked order.
    productions = Production.includes(:theater, :director, :screenings, :reviews)
                            .where(id: top_ids)
                            .index_by(&:id)
                            .values_at(*top_ids)
                            .compact

    render json: {
      productions: productions.map { |p| ProductionSerializer.list(p) },
      count: productions.size
    }
  end

  # GET /api/home/upcoming_premieres
  # Up to 4 productions whose premiere is still in the future.
  def upcoming_premieres
    productions = Production.active
                            .where("premiere_date > ?", Date.current)
                            .order(premiere_date: :asc)
                            .limit(4)
                            .includes(:theater, :director, :screenings, :reviews)

    render json: {
      productions: productions.map { |p| ProductionSerializer.list(p) },
      count: productions.size
    }
  end

  # GET /api/home/latest_reviews
  # 5 most recent matched reviews, with production + theater context for linking.
  def latest_reviews
    reviews = Review.matched
                    .recent
                    .limit(5)
                    .includes(production: %i[theater director])

    render json: {
      reviews: reviews.map { |r| ReviewSerializer.list(r) },
      count: reviews.size
    }
  end

  # GET /api/home/city_stats
  # Theater + production counts per major city, in a fixed display order.
  def city_stats
    theater_counts    = Theater.group(:city).count
    production_counts = Production.joins(:theater).group("theaters.city").count

    stats = CITY_ORDER.map do |city|
      {
        city:             city,
        theater_count:    theater_counts.fetch(city, 0),
        production_count: production_counts.fetch(city, 0)
      }
    end

    render json: { city_stats: stats }
  end
end
