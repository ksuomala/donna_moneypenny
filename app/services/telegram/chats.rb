module Telegram
  # Where an owner's messages go. A user has a chat of their own (users.telegram_chat_id) and a
  # household its own (households.telegram_chat_id), typically a group with the members in it;
  # a household without one is reached through its members' chats. Set with bin/rails
  # telegram:link. A user's chat is sent to with the user's own bot (users.telegram_bot_token, set
  # with bin/rails telegram:bot) when they have one, so the messages arrive in the chat with
  # their own assistant; a household's group chat and everyone else get the default bot.
  module Chats
    Recipient = Data.define(:chat_id, :bot_token) do
      def send_message(text) = Client.for(bot_token).send_message(chat_id: chat_id, text: text)
    end

    module_function

    # The chats for a user or a household, each with its bot; empty when nobody can be reached.
    def recipients(owner)
      return user_recipients(owner) unless owner.is_a?(Household)
      return [ Recipient.new(chat_id: owner.telegram_chat_id, bot_token: nil) ] if owner.telegram_chat_id.present?

      owner.users.order(:id).flat_map { |user| user_recipients(user) }.uniq(&:chat_id)
    end

    def for(owner) = recipients(owner).map(&:chat_id)

    def user_recipients(user)
      return [] if user.telegram_chat_id.blank?

      [ Recipient.new(chat_id: user.telegram_chat_id, bot_token: user.telegram_bot_token) ]
    end

    # The users and households with somewhere to send to.
    def owners
      users = User.where.not(telegram_chat_id: [ nil, "" ]).order(:id).to_a
      households = Household.order(:id).select { |household| self.for(household).any? }
      users + households
    end

    # The users whose transactions an owner's stats cover.
    def members(owner) = owner.is_a?(Household) ? owner.users.order(:id).to_a : [ owner ]

    def label(owner) = owner.is_a?(Household) ? owner.name : owner.email_address
  end
end
