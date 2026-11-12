# A stand-in for Telegram::Client in tests: records every message, with the bot token the client
# was built for, instead of sending it.
class TelegramStub
  Message = Data.define(:chat_id, :text, :token)

  attr_reader :messages
  attr_accessor :token

  def initialize(raises: nil)
    @messages = []
    @raises = raises
  end

  def send_message(chat_id:, text:)
    raise @raises if @raises

    @messages << Message.new(chat_id: chat_id, text: text, token: token)
    { "message_id" => @messages.size }
  end

  def self.with(stub = new)
    original = Telegram::Client.factory
    Telegram::Client.factory = ->(token) { stub.tap { stub.token = token } }
    yield stub
  ensure
    Telegram::Client.factory = original
  end
end
