# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_06_06_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "unaccent"

  create_table "click_events", force: :cascade do |t|
    t.bigint "production_id", null: false
    t.bigint "screening_id"
    t.bigint "user_id"
    t.string "target_url", null: false
    t.string "ip_hash"
    t.string "user_agent"
    t.string "referrer"
    t.datetime "clicked_at", null: false
    t.index ["clicked_at"], name: "index_click_events_on_clicked_at"
    t.index ["production_id", "clicked_at"], name: "index_click_events_on_production_id_and_clicked_at"
    t.index ["production_id"], name: "index_click_events_on_production_id"
    t.index ["screening_id"], name: "index_click_events_on_screening_id"
    t.index ["user_id"], name: "index_click_events_on_user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "production_id", null: false
    t.bigint "user_id", null: false
    t.text "body", null: false
    t.string "status", default: "published", null: false
    t.datetime "hidden_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id", "created_at"], name: "index_comments_on_production_id_and_created_at"
    t.index ["production_id"], name: "index_comments_on_production_id"
    t.index ["status"], name: "index_comments_on_status"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "directors", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.integer "birth_year"
    t.integer "death_year"
    t.string "nationality"
    t.text "bio"
    t.jsonb "notable_works", default: [], null: false
    t.string "photo_url"
    t.string "photo_credit"
    t.string "source_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_directors_on_lower_name", unique: true
    t.index ["slug"], name: "index_directors_on_slug", unique: true
  end

  create_table "productions", force: :cascade do |t|
    t.bigint "theater_id", null: false
    t.bigint "director_id", null: false
    t.string "slug", null: false
    t.string "title", null: false
    t.string "full_title"
    t.string "author"
    t.string "translator"
    t.string "based_on"
    t.string "genre"
    t.date "premiere_date"
    t.string "runtime"
    t.integer "runtime_minutes"
    t.string "age_rating"
    t.string "age_note"
    t.string "venue"
    t.string "language", default: "lt"
    t.text "description"
    t.text "director_quote"
    t.string "poster_url"
    t.string "video_url"
    t.string "source_url"
    t.jsonb "awards", default: [], null: false
    t.jsonb "creative_team", default: {}, null: false
    t.jsonb "cast_members", default: [], null: false
    t.integer "ensemble_size"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "active", null: false
    t.boolean "is_guest", default: false, null: false
    t.index ["director_id"], name: "index_productions_on_director_id"
    t.index ["genre"], name: "index_productions_on_genre"
    t.index ["is_guest"], name: "index_productions_on_is_guest"
    t.index ["premiere_date"], name: "index_productions_on_premiere_date"
    t.index ["status"], name: "index_productions_on_status"
    t.index ["theater_id", "slug"], name: "index_productions_on_theater_id_and_slug", unique: true
    t.index ["theater_id"], name: "index_productions_on_theater_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.bigint "production_id"
    t.string "author", null: false
    t.string "title"
    t.string "publication"
    t.string "issue"
    t.date "published_at"
    t.string "url"
    t.integer "rating"
    t.integer "rating_max", default: 10
    t.string "language", default: "lt"
    t.text "note"
    t.string "match_status", default: "pending", null: false
    t.float "match_confidence"
    t.datetime "matched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.float "radaras_score"
    t.index ["match_status"], name: "index_reviews_on_match_status"
    t.index ["production_id"], name: "index_reviews_on_production_id"
    t.index ["publication"], name: "index_reviews_on_publication"
    t.index ["published_at"], name: "index_reviews_on_published_at"
    t.index ["radaras_score"], name: "index_reviews_on_radaras_score"
  end

  create_table "screenings", force: :cascade do |t|
    t.bigint "production_id", null: false
    t.datetime "starts_at", null: false
    t.string "venue"
    t.string "city"
    t.string "note"
    t.string "ticket_url"
    t.boolean "is_premiere", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["city"], name: "index_screenings_on_city"
    t.index ["production_id", "starts_at"], name: "index_screenings_on_production_id_and_starts_at"
    t.index ["production_id"], name: "index_screenings_on_production_id"
    t.index ["starts_at"], name: "index_screenings_on_starts_at"
  end

  create_table "seen_articles", force: :cascade do |t|
    t.string "url", null: false
    t.string "publication", null: false
    t.string "outcome"
    t.datetime "seen_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["publication", "seen_at"], name: "index_seen_articles_on_publication_and_seen_at"
    t.index ["url"], name: "index_seen_articles_on_url", unique: true
  end

  create_table "theaters", force: :cascade do |t|
    t.string "slug", null: false
    t.string "name", null: false
    t.string "short_name"
    t.string "city", null: false
    t.string "address"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "phone"
    t.integer "founded_year"
    t.string "current_season"
    t.string "website_url"
    t.jsonb "venues", default: [], null: false
    t.text "description"
    t.string "photo_url"
    t.string "photo_credit"
    t.jsonb "social", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["city"], name: "index_theaters_on_city"
    t.index ["slug"], name: "index_theaters_on_slug", unique: true
  end

  create_table "user_ratings", force: :cascade do |t|
    t.bigint "production_id", null: false
    t.bigint "user_id"
    t.integer "rating", null: false
    t.string "session_id"
    t.string "ip_hash"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_id", "ip_hash"], name: "idx_user_ratings_ip_unique", unique: true, where: "((ip_hash IS NOT NULL) AND (user_id IS NULL) AND (session_id IS NULL))"
    t.index ["production_id", "session_id"], name: "idx_user_ratings_session_unique", unique: true, where: "(session_id IS NOT NULL)"
    t.index ["production_id", "user_id"], name: "idx_user_ratings_user_unique", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["production_id"], name: "index_user_ratings_on_production_id"
    t.index ["user_id"], name: "index_user_ratings_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", null: false
    t.string "name"
    t.string "avatar_url"
    t.string "provider", null: false
    t.string "uid", null: false
    t.string "role", default: "member", null: false
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  add_foreign_key "click_events", "productions"
  add_foreign_key "click_events", "screenings"
  add_foreign_key "click_events", "users"
  add_foreign_key "comments", "productions"
  add_foreign_key "comments", "users"
  add_foreign_key "productions", "directors"
  add_foreign_key "productions", "theaters"
  add_foreign_key "reviews", "productions"
  add_foreign_key "screenings", "productions"
  add_foreign_key "user_ratings", "productions"
  add_foreign_key "user_ratings", "users"
end
