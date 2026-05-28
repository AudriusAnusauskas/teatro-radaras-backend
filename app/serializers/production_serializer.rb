class ProductionSerializer
    # Compact list view — used by /api/productions index
    def self.list(production)
      {
        slug:           production.slug,
        title:          production.title,
        genre:          production.genre,
        premiere_date:  production.premiere_date,
        status:         production.status,
        description:    production.description,
        poster_url:     production.poster_url,
        age_rating:     production.age_rating,
        runtime:        production.runtime,
  
        theater: {
          slug:       production.theater.slug,
          name:       production.theater.name,
          short_name: production.theater.short_name,
          city:       production.theater.city
        },
  
        director: {
          slug: production.director.slug,
          name: production.director.name
        },
  
        critic_score:    production.critic_score,
        audience_score:  production.audience_score,
        audience_count:  production.audience_count,
  
        next_screening: serialize_screening(production.screenings.upcoming.first)
      }
    end
  
    # Full detail view — used by /api/productions/:slug
    def self.detail(production)
      comments = production.comments.visible.includes(:user).order(created_at: :desc)
      user_ids = comments.map(&:user_id).uniq
      ratings_by_user = UserRating
                        .where(production_id: production.id, user_id: user_ids)
                        .index_by(&:user_id)
  
      list(production).merge(
        full_title:     production.full_title,
        author:         production.author,
        translator:     production.translator,
        based_on:       production.based_on,
        runtime_minutes: production.runtime_minutes,
        age_note:       production.age_note,
        venue:          production.venue,
        language:       production.language,
        description:    production.description,
        director_quote: production.director_quote,
        video_url:      production.video_url,
        source_url:     production.source_url,
        awards:         production.awards,
        creative_team:  production.creative_team,
        cast:           production.cast_members,
        ensemble_size:  production.ensemble_size,
  
        upcoming_showings: production.screenings.upcoming.limit(20).map { |s| serialize_screening(s) },
        reviews:           production.reviews.matched.recent.map { |r| serialize_review(r) },
        comments:          comments.map { |c| CommentSerializer.list(c, ratings_by_user[c.user_id]) }
      )
    end
  
    def self.serialize_screening(screening)
      return nil unless screening

      {
        id:          screening.id,
        date:        screening.starts_at.to_date.iso8601,
        time:        screening.starts_at.strftime("%H:%M"),
        starts_at:   screening.starts_at.iso8601,
        venue:       screening.venue,
        city:        screening.city,
        ticket_url:  screening.ticket_url,
        is_premiere: screening.is_premiere
      }
    end
  
    def self.serialize_review(review)
      {
        author:       review.author,
        title:        review.title,
        publication:  review.publication,
        issue:        review.issue,
        published_at: review.published_at,
        url:          review.url,
        rating:       review.rating,
        rating_max:   review.rating_max,
        note:         review.note          # excerpt only — never full text
      }
    end
  end