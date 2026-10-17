# Static privacy policy and terms of service. These must stay publicly reachable
# (no login) because Enable Banking shows them to the user on the bank consent screen.
class LegalController < ApplicationController
  skip_before_action :require_owner

  def privacy
  end

  def terms
  end
end
