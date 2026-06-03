class ReviewClassifier
  # scraped: { title:, body (full preferred, excerpt fallback):, production_title:, director_name: optional }
  # Returns: { is_review: bool, radaras_score: Float|nil (1.0-5.0), quote: String|nil }
  def initialize(client: ClaudeClient.new)
    @client = client
  end

  def classify(article_title:, article_body:, production_title:, director_name: nil)
    system = <<~SYS
      Tu esi lietuvių teatro recenzijų analizės asistentas. Gauni straipsnį ir spektaklio pavadinimą.
      Nustatyk:
      1. Ar tai RECENZIJA apie nurodytą spektaklį (analitinis, vertinamasis tekstas apie vieną pastatymą), o NE interviu, anonsas, festivalio apžvalga ar straipsnis apie kelis spektaklius.
      2. Jei recenzija — įvertink bendrą kritiko požiūrio teigiamumą skalėje nuo 1.0 iki 5.0 (1=labai neigiamas, 3=mišrus, 5=labai teigiamas). Tai NĖRA kritiko balas — tai teksto tono interpretacija.
      3. Jei recenzija — ištrauk vieną reprezentatyvią, vertinamąją citatą VERBATIM iš teksto (iki 200 simbolių, pilnas sakinys, lietuviškai).

      SVARBU dėl JSON galiojimo: citatos lauke ("quote") jokiu būdu nenaudok ASCII dvigubų kabučių (").
      Vietoj jų naudok lietuviškas kabutes („ ir “) arba escape'ink kaip \". Kitaip JSON bus sugadintas.

      Atsakyk TIK JSON formatu, be jokio papildomo teksto:
      {"is_review": true/false, "radaras_score": 1.0-5.0 arba null, "quote": "..." arba null}
    SYS

    director_line = director_name.present? ? "\nRežisierius: #{director_name}" : ""

    user = <<~USR
      Spektaklis: „#{production_title}“#{director_line}
      Straipsnio antraštė: #{article_title}
      Straipsnio tekstas:
      #{article_body}
    USR

    raw = @client.complete(system: system, user: user, max_tokens: 1024)
    parsed = parse_json(raw)

    {
      is_review: parsed["is_review"] == true,
      radaras_score: parsed["radaras_score"]&.to_f,
      quote: parsed["quote"]
    }
  rescue ClaudeClient::RateLimitError
    # Never miscategorize a rate-limited article as "not a review" —
    # let it bubble up so the orchestrator can record it as an error.
    raise
  rescue StandardError => e
    Rails.logger.error("[ReviewClassifier] #{e.message}")
    { is_review: false, radaras_score: nil, quote: nil, error: e.message }
  end

  private

  # Returns a hash with string keys "is_review", "radaras_score", "quote".
  # Tries strict JSON first; falls back to field extraction because the model
  # often emits Lithuanian quotes that include unescaped ASCII (") inside the
  # quote value, which breaks JSON parsing.
  def parse_json(raw)
    json = raw.to_s.gsub(/```json|```/, "").strip
    json = json[/\{.*\}/m] || json

    JSON.parse(json)
  rescue JSON::ParserError
    extract_fields(json)
  end

  def extract_fields(text)
    is_review = text[/"is_review"\s*:\s*(true|false)/, 1]
    raise JSON::ParserError, "no is_review field in: #{text[0, 120]}" if is_review.nil?

    score = text[/"radaras_score"\s*:\s*([0-9]+(?:\.[0-9]+)?)/, 1]
    quote = text[/"quote"\s*:\s*"(.*?)"\s*[,}]?\s*\z/m, 1] ||
            text[/"quote"\s*:\s*"(.*)/m, 1]&.sub(/"\s*\}?\s*\z/, "")

    {
      "is_review" => is_review == "true",
      "radaras_score" => score,
      "quote" => quote&.strip&.presence
    }
  end
end
