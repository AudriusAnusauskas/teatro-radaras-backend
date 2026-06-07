class ClaudeClient
  API_URL = "https://api.anthropic.com/v1/messages"
  MODEL = "claude-haiku-4-5-20251001" # cost-efficient for classification; adjust if needed

  MAX_RATE_LIMIT_RETRIES = 3
  # Used when the 429 response carries no usable retry-after header.
  BACKOFF_SCHEDULE = [10, 30, 60].freeze

  # Raised when the API keeps returning 429 after all retries are exhausted,
  # so callers (e.g. the import orchestrator) can treat it as a recoverable
  # error rather than a classification result.
  class RateLimitError < StandardError; end

  def initialize(api_key: ENV["ANTHROPIC_API_KEY"])
    @api_key = api_key
    raise "ANTHROPIC_API_KEY not set" if @api_key.to_s.empty?
  end

  # Returns Claude's response text (caller parses JSON if needed)
  def complete(system:, user:, max_tokens: 1024, model: MODEL)
    attempt = 0

    loop do
      response = post_message(system: system, user: user, max_tokens: max_tokens, model: model)

      return extract_text(response) if response.status == 200

      if response.status == 429
        attempt += 1
        if attempt > MAX_RATE_LIMIT_RETRIES
          raise RateLimitError, "Claude API rate limited (429) after #{MAX_RATE_LIMIT_RETRIES} retries"
        end

        delay = retry_after_seconds(response) || BACKOFF_SCHEDULE[attempt - 1]
        Rails.logger.warn("[ClaudeClient] 429 rate limited — retry #{attempt}/#{MAX_RATE_LIMIT_RETRIES} after #{delay}s")
        sleep(delay)
        next
      end

      raise "Claude API error #{response.status}: #{response.body}"
    end
  end

  private

  def post_message(system:, user:, max_tokens:, model: MODEL)
    # Faraday :retry handles transient network/timeout errors only (not 429,
    # which we honor explicitly via the retry-after header above).
    conn = Faraday.new do |f|
      f.request :retry, max: 2
      f.adapter Faraday.default_adapter
    end

    conn.post(API_URL) do |req|
      req.options.timeout = 60
      req.headers["x-api-key"] = @api_key
      req.headers["anthropic-version"] = "2023-06-01"
      req.headers["content-type"] = "application/json"
      req.body = {
        model: model,
        max_tokens: max_tokens,
        system: system,
        messages: [{ role: "user", content: user }]
      }.to_json
    end
  end

  def extract_text(response)
    JSON.parse(response.body).dig("content", 0, "text")
  end

  # Anthropic returns retry-after in whole seconds. Returns Float seconds or nil.
  def retry_after_seconds(response)
    raw = response.headers["retry-after"] || response.headers["Retry-After"]
    return nil if raw.to_s.strip.empty?

    seconds = Float(raw, exception: false)
    return seconds if seconds

    # Fallback: an HTTP-date value.
    (Time.httpdate(raw) - Time.now).ceil
  rescue ArgumentError
    nil
  end
end
