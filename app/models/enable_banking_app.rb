# A user's own application in the Enable Banking Control Panel, activated in restricted mode with
# the user's own accounts: it can reach only those, and needs no contract with Enable Banking.
# Created without credentials when the user first opens the settings page, so its callback URL
# can be registered with the application; the application ID and key are entered after that.
class EnableBankingApp < ApplicationRecord
  belongs_to :user
  has_many :bank_connections, dependent: :restrict_with_error

  encrypts :private_key
  has_secure_token :callback_token

  normalizes :application_id, with: ->(id) { id.strip.presence }
  normalizes :private_key, with: ->(key) { key.strip.presence && "#{key.strip}\n" }

  validates :application_id, uniqueness: true, allow_nil: true
  validates :application_id, :private_key, presence: true, on: :credentials
  validate :private_key_is_an_rsa_private_key, if: :private_key?

  def configured?
    application_id.present? && private_key.present?
  end

  def client
    EnableBanking::Client.for(self)
  end

  private

  def private_key_is_an_rsa_private_key
    errors.add(:private_key, "is not an RSA private key") unless OpenSSL::PKey::RSA.new(private_key).private?
  rescue OpenSSL::PKey::PKeyError
    errors.add(:private_key, "is not a PEM-encoded RSA private key")
  end
end
