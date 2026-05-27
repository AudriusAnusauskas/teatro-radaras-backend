class ScreeningSerializer
  def self.list(screening)
    production = screening.production
    theater = production.theater
    director = production.director

    {
      id: screening.id,
      date: screening.starts_at.to_date.iso8601,
      time: screening.starts_at.strftime("%H:%M"),
      starts_at: screening.starts_at.iso8601,
      venue: screening.venue,
      ticket_url: screening.ticket_url,
      is_premiere: screening.is_premiere,
      production: {
        slug: production.slug,
        title: production.title,
        poster_url: production.poster_url,
        genre: production.genre
      },
      theater: {
        slug: theater.slug,
        name: theater.name,
        short_name: theater.short_name,
        city: theater.city
      },
      director: director ? {
        slug: director.slug,
        name: director.name
      } : nil
    }
  end
end
