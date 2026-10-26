# A record that belongs to one user. A record created during a request goes to the signed-in
# user; one created by a rake task goes to the user it acts for (Current.user, set from
# EMAIL=..., else the owner). Background jobs set the user explicitly.
module OwnedByUser
  extend ActiveSupport::Concern

  included do
    # Optional until user_id is NOT NULL: rows from before users existed have no owner until
    # bin/rails users:create gives them to the first user.
    belongs_to :user, optional: true, default: -> { default_owner }
  end

  private

  def default_owner
    Current.user || User.owner
  end
end
