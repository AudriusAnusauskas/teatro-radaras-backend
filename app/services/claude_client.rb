class ClaudeClient
  API_URL = "https://api.anthropic.com/v1/messages"
  MODEL = "claude-haiku-4-5-20251001" # cost-efficient for classification; adjust if needed

  def initialize(api_key: ENV["ANTHROPIC_API_KEY"])
    @api_key = api_key
    raise "ANTHROPIC_API_KEY not set" if @api_key.to_s.empty?
  end

  # Returns Claude's response text (caller parses JSON if needed)
  def complete(system:, user:, max_tokens: 1024)
    conn = Faraday.new do |f|
      f.request :retry, max: 2
      f.adapter Faraday.default_adapter
    end

    response = conn.post(API_URL) do |req|
      req.options.timeout = 60
      req.headers["x-api-key"] = @api_key
      req.headers["anthropic-version"] = "2023-06-01"
      req.headers["content-type"] = "application/json"
      req.body = {
        model: MODEL,
        max_tokens: max_tokens,
        system: system,
        messages: [{ role: "user", content: user }]
      }.to_json
    end

    raise "Claude API error #{response.status}: #{response.body}" unless response.status == 200

    body = JSON.parse(response.body)
    body.dig("content", 0, "text")
  end
end
