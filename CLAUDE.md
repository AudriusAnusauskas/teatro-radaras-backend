# Teatro radaras — Backend

Lietuvos teatro portalas (Rotten Tomatoes for theater). Rails API + Next.js frontend.

## Stack

- **Rails 7.2** API mode, Ruby 3.3+
- **PostgreSQL** — pagrindinė DB
- **Sidekiq + Redis** — background jobs (scrapers, review matching)
- **Nokogiri + Ferrum** — web scraping
- **Claude API (Haiku)** — review classification ir production matching
- **Hosting:** Railway (backend), Vercel (frontend `demo.teatroradaras.lt`)
- **API base:** `api.teatroradaras.lt`

## Modeliai

```
Theater        slug unique, has_many :productions
Director       slug unique, has_many :productions
Production     belongs_to :theater, :director
               has_many :screenings, :reviews
               dependent: :destroy visur
Screening      belongs_to :production (vienas rodymas — data + laikas)
Review         belongs_to :production
               source: tik "7md" arba "menufaktura" (partner-only policy)
               url-based deduplication
User           Devise + Google OAuth
UserRating     belongs_to :production (anon OK — session_id/ip_hash)
Comment        belongs_to :user, :production (auth required)
ClickEvent     ticket click tracking
```

**Svarbu:** `cast` lieka `jsonb` array (Actor modelis deferred). `creative_team` — jsonb.

## Review pipeline — kritinės taisyklės

1. **Partner-only policy:** tik 7md.lt ir menufaktura.lt recenzijos. Kitos — ignoruojamos net jei rastos.
2. **`dependent: :destroy`** — ne `:nullify`. Production delete'as cascade'ina reviews.
3. **Merge operacijos:** prieš trinant duplicate production — pervesti reviews į išliekantį įrašą.
4. **`RateLimitError` turi propagate'inti** — ne swallow'inti. 429 != "not a review". Reikia retry-after backoff.
5. **`REQUEST_DELAY` >= 4s** tarp scraping requests.
6. **`radaras_score`** skaičiuojamas Ruby serializer'yje (ne SQL AVG) — avoid N+1.

## Scrapers

- `SevenmdReviewScraper` — 7md.lt recenzijos
- Menufaktura scraper — menufaktura.lt recenzijos  
- `ReviewClassifier` — Claude Haiku, JSON response su Lithuanian quotation marks fallback regex
- `SevenmdReviewMatcher` / `MenufakturaProductionMatcher` — production matching
- `ScrapeReviewsJob` — Sidekiq job

**`ANTHROPIC_API_KEY`** — Railway environment variable (ne tik `.env`). `dotenv-rails` neveikia `RAILS_ENV=production` — naudoti `set -a; source .env; set +a` lokaliai production mode'u.

## API endpointai

```
GET  /api/theaters
GET  /api/theaters/:slug
GET  /api/productions          ?city, ?theater_slug, ?genre, ?premiere_only, ?min_rating
GET  /api/productions/:slug
GET  /api/directors
GET  /api/directors/:slug
GET  /api/reviews              ?publication, ?theater_slug, ?production_slug, ?year
GET  /api/search?q=

POST   /api/ratings            (anon OK)
POST   /api/comments           (auth required)
DELETE /api/comments/:id       (auth required)
GET    /out?url=...&production_id=...   (ticket redirect + tracking)
```

## Dabartinė būsena

- ~480 reviews, ~179 productions su recenzijų aprėptimi, 0 orphans
- Frontend MVP complete (`/spektakliai`, `/spektaklis/[slug]`, `/recenzijos`, kt.)
- `radaras_score` + `critic_review_count` wired per Rails serializer į frontend
- Homepage sekcijos dar naudoja mock duomenis — reikia real data wiring

## Ko vengti

- **Aktorių modelio dabar** — `cast` lieka jsonb
- **SQL AVG `radaras_score`** — skaičiuoti Ruby serializer'yje
- **`dependent: :nullify` ant reviews** — tik `:destroy`
- **Rate limit klaidų swallow'inimas** — turi propagate'inti
- **Copyright pažeidimai** — recenzijos tik kaip anonsas + link į originalą

## Darbo stilius

- Dirbu Vinted (Rails/backend gerai, Devise/Sidekiq advanced — mažiau)
- Iteratyvus, ne over-planning
- Diskusija lietuviškai, kodas angliškai
- Commitu ir pushinau pats po review
