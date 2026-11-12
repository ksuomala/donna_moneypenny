require "test_helper"

class Telegram::ChatsTest < ActiveSupport::TestCase
  BOT = "123456:own-bot_token".freeze

  setup do
    @user = users(:one)
    @other = users(:two)
  end

  test "a user's chat gets the user's own bot, or the default one without it" do
    @user.update!(telegram_chat_id: "111", telegram_bot_token: BOT)
    @other.update!(telegram_chat_id: "222")

    TelegramStub.with do |stub|
      Telegram::Chats.recipients(@user).each { |recipient| recipient.send_message("hi") }
      Telegram::Chats.recipients(@other).each { |recipient| recipient.send_message("hi") }

      assert_equal [ [ "111", BOT ], [ "222", Telegram::Client.bot_token ] ], stub.messages.map { |m| [ m.chat_id, m.token ] }
    end
  end

  test "a household's group chat gets the default bot, and without one each member's chat gets the member's bot" do
    household = Household.create!(name: "Us", telegram_chat_id: "-500")
    @user.update!(household: household, telegram_chat_id: "111", telegram_bot_token: BOT)
    @other.update!(household: household, telegram_chat_id: "222")

    assert_equal [ Telegram::Chats::Recipient.new(chat_id: "-500", bot_token: nil) ], Telegram::Chats.recipients(household)

    household.update!(telegram_chat_id: nil)
    assert_equal [ [ "111", BOT ], [ "222", nil ] ], Telegram::Chats.recipients(household).map { |r| [ r.chat_id, r.bot_token ] }.sort_by(&:first)
  end

  test "the token is stored encrypted and must look like a bot token" do
    @user.update!(telegram_bot_token: "  #{BOT}  ")
    assert_equal BOT, @user.reload.telegram_bot_token
    assert_not_includes User.connection.select_value("SELECT telegram_bot_token FROM users WHERE id = #{@user.id}"), BOT

    assert_not @user.update(telegram_bot_token: "not a token")
    @user.update!(telegram_bot_token: "")
    assert_nil @user.reload.telegram_bot_token
  end
end
