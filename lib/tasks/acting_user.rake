# Rake tasks that read or write one user's data act for the owner, or for the user given as
# EMAIL=... Records created by the task belong to that user (OwnedByUser).
def acting_user
  Current.user ||= ENV["EMAIL"].present? ? User.find_by!(email_address: ENV["EMAIL"].strip.downcase) : User.owner
end
