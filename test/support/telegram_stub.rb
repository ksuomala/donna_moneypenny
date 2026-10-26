# A stand-in for Telegram::Client in tests: records every message instead of sending it.
class TelegramStub
  Message = Data.define(:chat_id, :text)

  attr_reader :messages

  def initialize(raises: nil)
    @messages = []
    @raises = raises
  end

  def send_message(chat_id:, text:)
    raise @raises if @raises

    @messages << Message.new(chat_id: chat_id, text: text)
    { "message_id" => @messages.size }
  end

  def self.with(stub = new)
    original = Telegram::Client.factory
    Telegram::Client.factory = -> { stub }
    yield stub
  ensure
    Telegram::Client.factory = original
  end
end
