module BankTransactions
  class Categorizer
    # OpenAI's Responses API with a strict JSON schema answer, the same Decisions schema the
    # Claude backend uses. Raw HTTP: there is no official Ruby SDK.
    class OpenaiBackend
      URL = "https://api.openai.com/v1/responses"
      MAX_OUTPUT_TOKENS = 16_000
      Decision = Struct.new(:transaction_id, :category_id, :loan_id, :confidence, :reason, keyword_init: true)

      def self.api_key = Rails.application.credentials.dig(:openai, :api_key).presence || ENV["OPENAI_API_KEY"].presence

      DEFAULT_CLIENT_FACTORY = -> { HttpClient.new(url: URL, api_key: OpenaiBackend.api_key) }
      class_attribute :client_factory, default: DEFAULT_CLIENT_FACTORY

      def self.configured? = client_factory != DEFAULT_CLIENT_FACTORY || api_key.present?

      def initialize(model:, effort:, client: nil)
        @model = model
        @effort = effort
        @client = client || self.class.client_factory.call
      end

      def decide(prompt:, context:, user_message:, **)
        body = {
          model: @model,
          instructions: "#{prompt}\n\n#{context}",
          input: [ { role: "user", content: user_message } ],
          max_output_tokens: MAX_OUTPUT_TOKENS,
          text: { format: { type: "json_schema", name: "decisions", schema: Decisions.to_json_schema, strict: true } }
        }
        body[:reasoning] = { effort: @effort } if @effort.present?
        response = @client.post(body)

        if response["status"] == "incomplete"
          reason = response.dig("incomplete_details", "reason")
          raise(reason == "max_output_tokens" ? Truncated : Refused, "Answer incomplete: #{reason}")
        end
        content = Array(response["output"]).select { |item| item["type"] == "message" }.flat_map { |item| Array(item["content"]) }
        raise Refused, "Model refused the batch" if content.any? { |part| part["type"] == "refusal" }
        text = content.find { |part| part["type"] == "output_text" }&.dig("text")
        raise Error, "No answer in the response" if text.blank?

        decisions = JSON.parse(text).fetch("decisions").map { |row| Decision.new(**row.slice(*Decision.members.map(&:to_s)).symbolize_keys) }
        usage = response.fetch("usage", {})
        cached = usage.dig("input_tokens_details", "cached_tokens").to_i
        Response.new(decisions: decisions, model: response["model"].to_s,
                     usage: Usage.new(input_tokens: usage["input_tokens"].to_i - cached, output_tokens: usage["output_tokens"].to_i,
                                      cache_read_input_tokens: cached, cache_creation_input_tokens: 0))
      rescue JSON::ParserError, KeyError => e
        raise Error, "Unusable answer: #{e.message.first(200)}"
      end
    end
  end
end
