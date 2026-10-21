# A record that belongs to one user. A record created during a request goes to the signed-in
# user; one created by a rake task or background job goes to the owner (User.owner), until those
# run per user.
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
