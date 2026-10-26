module BankTransactions
  class Categorizer
    # Claude through the official SDK, with the answer constrained to the Decisions schema.
    class AnthropicBackend
      MAX_TOKENS = 16_000
      REQUEST_OPTIONS = { timeout: 600, max_retries: 3 }.freeze

      def self.api_key = Rails.application.credentials.dig(:anthropic, :api_key).presence || ENV["ANTHROPIC_API_KEY"].presence

      DEFAULT_CLIENT_FACTORY = -> { Anthropic::Client.new(api_key: AnthropicBackend.api_key) }
      class_attribute :client_factory, default: DEFAULT_CLIENT_FACTORY

      def self.configured? = client_factory != DEFAULT_CLIENT_FACTORY || api_key.present?

      def initialize(model:, effort:, client: nil)
        @model = model
        @effort = effort
        @client = client || self.class.client_factory.call
      end

      def decide(prompt:, context:, user_message:, **)
        message = @client.messages.create(
          model: @model,
          max_tokens: MAX_TOKENS,
          system_: [
            { type: "text", text: prompt, cache_control: { type: "ephemeral" } },
            { type: "text", text: context, cache_control: { type: "ephemeral" } }
          ],
          messages: [ { role: "user", content: user_message } ],
          output_config: output_config,
          request_options: REQUEST_OPTIONS
        )

        raise Truncated, "Answer hit #{MAX_TOKENS} tokens" if message.stop_reason == :max_tokens
        raise Refused, "Model refused the batch" if message.stop_reason == :refusal
        parsed = message.parsed_output
        raise Error, "Unusable answer: #{parsed.inspect.first(200)}" unless parsed.is_a?(Decisions)

        usage = message.usage
        Response.new(decisions: parsed.decisions, model: message.model.to_s,
                     usage: Usage.new(input_tokens: usage.input_tokens.to_i, output_tokens: usage.output_tokens.to_i,
                                      cache_read_input_tokens: usage.cache_read_input_tokens.to_i,
                                      cache_creation_input_tokens: usage.cache_creation_input_tokens.to_i))
      end

      # Haiku 4.5 has no effort setting (the API rejects it), the newer models take one.
      def output_config
        @effort.present? && !@model.to_s.start_with?("claude-haiku-4") ? { effort: @effort, format: Decisions } : { format: Decisions }
      end
    end
  end
end
