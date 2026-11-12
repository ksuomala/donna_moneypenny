# A bearer token for the agent API (/api). It belongs to one user, and a request made with it
# sees and changes only that user's data. Only a SHA-256 digest is stored: the token itself is
# shown once, when bin/rails api_tokens:create makes it.
class ApiToken < ApplicationRecord
  PREFIX = "donna_".freeze

  belongs_to :user

  # The plain token, only on the record generate! returns.
  attr_accessor :token

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token_digest, presence: true, uniqueness: true

  def self.generate!(user:, name:)
    token = "#{PREFIX}#{SecureRandom.base58(40)}"
    create!(user: user, name: name, token_digest: digest(token)).tap { |record| record.token = token }
  end

  # The token's record, or nil for an unknown one; records the use.
  def self.authenticate(token)
    find_by(token_digest: digest(token))&.tap { |record| record.update_column(:last_used_at, Time.current) }
  end

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)
end
