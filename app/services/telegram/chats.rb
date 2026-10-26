module Telegram
  # Where an owner's messages go. A user has a chat of their own (users.telegram_chat_id) and a
  # household its own (households.telegram_chat_id), typically a group with the members in it;
  # a household without one is reached through its members' chats. Set with bin/rails
  # telegram:link.
  module Chats
    module_function

    # The chat ids for a user or a household; empty when nobody can be reached.
    def for(owner)
      return [ owner.telegram_chat_id ].compact_blank unless owner.is_a?(Household)
      return [ owner.telegram_chat_id ] if owner.telegram_chat_id.present?

      owner.users.order(:id).map(&:telegram_chat_id).compact_blank.uniq
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
