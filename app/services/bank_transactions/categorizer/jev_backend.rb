module BankTransactions
  class Categorizer
    # TypeSafe's Jev, a decision model: it doesn't write text, it answers typed questions about a
    # state with calibrated probabilities. The state is the same prompt, context and batch the
    # LLM backends read; every transaction becomes one choice question over the categories and
    # one over the loans. A choice is confident when its confidence reaches the threshold
    # (CATEGORIZER_JEV_CONFIDENCE). Jev gives no reasons, so the reason is the probabilities.
    class JevBackend
      URL = "https://api.typesafe.ai/v1/systemone"
      NO_LOAN = "none"
      Decision = Struct.new(:transaction_id, :category_id, :loan_id, :confidence, :reason, keyword_init: true)

      def self.api_key = Rails.application.credentials.dig(:typesafe, :api_key).presence || ENV["TYPESAFE_API_KEY"].presence

      DEFAULT_CLIENT_FACTORY = -> { HttpClient.new(url: URL, api_key: JevBackend.api_key, timeout: 120) }
      class_attribute :client_factory, default: DEFAULT_CLIENT_FACTORY

      def self.configured? = client_factory != DEFAULT_CLIENT_FACTORY || api_key.present?

      def initialize(model:, client: nil, threshold: Rails.configuration.x.categorizer.jev_confidence, **)
        @model = model
        @threshold = threshold
        @client = client || self.class.client_factory.call
      end

      def decide(prompt:, context:, user_message:, transactions:, categories:, loans:)
        category_choices = categories.to_h { |c| [ "c#{c.id}", c.parent ? "#{c.parent.name} / #{c.name}" : c.name ] }
        loan_choices = loans.to_h { |l| [ "l#{l.id}", l.name ] }.merge(NO_LOAN => "Not a loan transaction, or no loan matches it")
        questions = transactions.each_with_object({}) do |t, all|
          label = "transaction #{t.id} (#{t.occurred_on}, #{t.amount.to_s("F")} #{t.currency}, #{t.counterparty_name.presence || "no counterparty"})"
          all["t#{t.id}"] = { type: "choice", criteria: category_choices,
                              instructions: "Which category does #{label} belong to? Decide by the rules, the category descriptions and the earlier decisions in the state." }
          all["l#{t.id}"] = { type: "choice", criteria: loan_choices,
                              instructions: "If #{label} is a loan transaction, which loan does it belong to, by the loan descriptions in the state?" }
        end

        response = @client.post(model: @model, state: "#{prompt}\n\n#{context}\n\n#{user_message}", questions: questions)
        answers = response.fetch("answers")
        decisions = transactions.filter_map do |t|
          answer = answers["t#{t.id}"] or next
          loan = answers["l#{t.id}"]
          Decision.new(transaction_id: t.id, category_id: answer["choice"].to_s.delete_prefix("c").to_i,
                       loan_id: (loan["choice"].delete_prefix("l").to_i if loan && loan["choice"] != NO_LOAN),
                       confidence: answer["confidence"].to_f >= @threshold ? "confident" : "unsure",
                       reason: reason(answer, category_choices))
        end
        usage = response.fetch("usage", {})
        Response.new(decisions: decisions, model: response["model"].to_s,
                     usage: Usage.new(input_tokens: usage["input_tokens"].to_i, output_tokens: usage["output_tokens"].to_i,
                                      cache_read_input_tokens: 0, cache_creation_input_tokens: 0))
      rescue KeyError, NoMethodError => e
        raise Error, "Unusable answer: #{e.message.first(200)}"
      end

      private

      # "confidence 0.93; Groceries 0.95, Cafes 0.03": the top two choices.
      def reason(answer, choices)
        top = answer.fetch("probabilities", {}).sort_by { |_, p| -p.to_f }.first(2).map { |key, p| "#{choices[key] || key} #{p.to_f.round(2)}" }
        "confidence #{answer["confidence"].to_f.round(2)}; #{top.join(", ")}"
      end
    end
  end
end
