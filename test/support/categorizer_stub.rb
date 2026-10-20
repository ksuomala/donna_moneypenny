# A stand-in for Anthropic::Client in categorizer tests: answers every messages.create with
# decisions built by the given block (transaction ids in the batch => decision hashes), or
# raises the given error. Records the requests.
class CategorizerStub
  Message = Struct.new(:stop_reason, :parsed_output, :usage, :model, keyword_init: true)
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens, keyword_init: true)

  attr_reader :requests

  def initialize(stop_reason: :end_turn, raises: nil, &decide)
    @stop_reason = stop_reason
    @raises = raises
    @decide = decide || ->(ids) { [] }
    @requests = []
  end

  def messages = self

  def create(**params)
    @requests << params
    raise @raises.shift if @raises.is_a?(Array) && @raises.any?
    raise @raises if @raises.is_a?(Exception)

    ids = params[:messages].sole[:content].lines.reject { |l| l.start_with?("#") }.take_while { |l| l.strip.present? }.map { |l| l.split("\t").first.to_i }
    decisions = Anthropic::Internal::Type::Converter.coerce(BankTransactions::Categorizer::Decisions, { decisions: @decide.call(ids) })
    Message.new(stop_reason: @stop_reason, parsed_output: decisions, model: "claude-test",
                usage: Usage.new(input_tokens: 1000, output_tokens: 100, cache_read_input_tokens: 800, cache_creation_input_tokens: 0))
  end

  def self.with(client)
    original = BankTransactions::Categorizer.client_factory
    BankTransactions::Categorizer.client_factory = -> { client }
    yield
  ensure
    BankTransactions::Categorizer.client_factory = original
  end
end
