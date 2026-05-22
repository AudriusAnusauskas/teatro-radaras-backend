# db/seeds.rb
#
# Idempotent seed from db/seeds/data.json.
# Re-runnable: lookups by slug, attributes overwritten on each run.
#
# Run: bin/rails db:seed
# Reset + reseed: bin/rails db:reset

require "json"

SEED_PATH = Rails.root.join("db/seeds/data.json")
abort "Seed file not found at #{SEED_PATH}" unless SEED_PATH.exist?

data = JSON.parse(SEED_PATH.read)

puts "Seeding from #{SEED_PATH} — #{data['theaters'].size} theaters, " \
     "#{data['directors'].size} directors, #{data['productions'].size} productions"

# ----------------------------------------------------------------------------
# Theaters
# ----------------------------------------------------------------------------
data["theaters"].each do |t|
  theater = Theater.find_or_initialize_by(slug: t["slug"])
  theater.assign_attributes(
    name:           t["name"],
    short_name:     t["shortName"],
    city:           t["city"],
    address:        t["address"],
    latitude:       t.dig("coordinates", "lat"),
    longitude:      t.dig("coordinates", "lng"),
    phone:          t["phone"],
    founded_year:   t["foundedYear"],
    current_season: t["currentSeason"],
    website_url:    t["websiteUrl"],
    venues:         t["venues"] || [],
    description:    t["description"],
    photo_url:      t["photoUrl"],
    photo_credit:   t["photoCredit"],
    social:         t["social"] || {}
  )
  theater.save!
end
puts "  ✓ #{Theater.count} theaters"

# ----------------------------------------------------------------------------
# Directors
# ----------------------------------------------------------------------------
data["directors"].each do |d|
  director = Director.find_or_initialize_by(slug: d["slug"])
  director.assign_attributes(
    name:          d["name"],
    birth_year:    d["birthYear"],
    death_year:    d["deathYear"],
    nationality:   d["nationality"],
    bio:           d["bio"],
    notable_works: d["notableWorks"] || [],
    photo_url:     d["photoUrl"],
    photo_credit:  d["photoCredit"],
    source_url:    d["sourceUrl"]
  )
  director.save!
end
puts "  ✓ #{Director.count} directors"

# ----------------------------------------------------------------------------
# Productions (+ nested screenings & reviews)
# ----------------------------------------------------------------------------
data["productions"].each do |p|
  theater  = Theater.find_by!(slug: p["theaterSlug"])
  director = Director.find_by!(slug: p["directorSlug"])

  production = Production.find_or_initialize_by(slug: p["slug"])
  production.assign_attributes(
    theater:         theater,
    director:        director,
    title:           p["title"],
    full_title:      p["fullTitle"],
    author:          p["author"],
    translator:      p["translator"],
    based_on:        p["basedOn"],
    genre:           p["genre"],
    premiere_date:   p["premiereDate"],
    runtime:         p["runtime"],
    runtime_minutes: p["runtimeMinutes"],
    age_rating:      p["ageRating"],
    age_note:        p["ageNote"],
    venue:           p["venue"],
    language:        p["language"] || "lt",
    description:     p["description"],
    director_quote:  p["directorQuote"],
    poster_url:      p["posterUrl"],
    video_url:       p["videoUrl"],
    source_url:      p["sourceUrl"],
    awards:          p["awards"] || [],
    creative_team:   p["creativeTeam"] || {},   # jsonb — kept camelCase for now
    cast_members:    p["cast"] || [],
    ensemble_size:   p["ensembleSize"]
  )
  production.save!

  # --- Screenings (replace on reseed to avoid stale showings)
  production.screenings.destroy_all

  (p["upcomingShowings"] || []).each do |s|
    starts_at = Time.zone.parse("#{s['date']} #{s['time']}")
    production.screenings.create!(
      starts_at:   starts_at,
      venue:       s["venue"],
      city:        s["city"],
      note:        s["note"],
      ticket_url:  s["ticketUrl"],
      is_premiere: s["date"] == p["premiereDate"]
    )
  end

  # --- Reviews (upsert by url+publication, treat seed data as already matched)
  (p["reviews"] || []).each do |r|
    # Scope dedup to this production — same (publication, author, title, published_at)
    # within one production identifies the same review, regardless of URL presence.
    review = production.reviews.find_or_initialize_by(
      publication:  r["publication"],
      author:       r["author"],
      title:        r["title"],
      published_at: r["publishedAt"]
    )
    review.assign_attributes(
      url:              r["url"],
      rating:           r["rating"],
      rating_max:       r["ratingMax"] || 10,
      language:         r["language"] || "lt",
      issue:            r["issue"],
      note:             r["note"],
      match_status:     "matched",
      match_confidence: 1.0,
      matched_at:       Time.current
    )
    review.save!
  end
end
puts "  ✓ #{Production.count} productions, #{Screening.count} screenings, #{Review.count} reviews"

puts "Done."
