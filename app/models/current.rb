class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # The user a rake task acts for (EMAIL=..., see lib/tasks/acting_user.rake); in a request
  # it is the signed-in session's user.
  attribute :user

  def user = super || session&.user
end
