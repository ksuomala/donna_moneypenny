require "test_helper"

class Telegram::ClientTest < ActiveSupport::TestCase
  test "the endpoint keeps the token's colon inside the path" do
    uri = Telegram::Client.new(token: "123456:ABC-def_ghi").endpoint("sendMessage")

    assert_kind_of URI::HTTPS, uri
    assert_equal "https://api.telegram.org/bot123456:ABC-def_ghi/sendMessage", uri.to_s
  end

  test "sending without a token raises before any request" do
    error = assert_raises(Telegram::Client::Error) { Telegram::Client.new(token: nil).send_message(chat_id: 1, text: "hi") }

    assert_match "No Telegram bot token", error.message
  end
end
