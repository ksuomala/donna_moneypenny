class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # Single-user app: everything sits behind HTTP basic auth, with the login kept in the
  # encrypted credentials (basic_auth.username / basic_auth.password).
  before_action :require_owner

  private

  def require_owner
    authenticate_or_request_with_http_basic("Donna Moneypenny") do |username, password|
      expected = Rails.application.credentials.basic_auth
      next false if expected.blank?

      ActiveSupport::SecurityUtils.secure_compare(username, expected[:username]) &
        ActiveSupport::SecurityUtils.secure_compare(password, expected[:password])
    end
  end
end
