class ReviewSerializer
    def self.list(review)
      {
        author:       review.author,
        title:        review.title,
        publication:  review.publication,
        issue:        review.issue,
        published_at: review.published_at,
        url:          review.url,
        rating:       review.rating,
        rating_max:   review.rating_max,
        note:         review.note,
        production:   serialize_production(review.production)
      }
    end
  
    def self.serialize_production(production)
      return nil unless production
  
      {
        slug:               production.slug,
        title:              production.title,
        theater_short_name: production.theater.short_name,
        poster_url:         production.poster_url,
        theater_slug:       production.theater.slug,
        director: {
          slug: production.director.slug,
          name: production.director.name
        }
      }
    end
  end
