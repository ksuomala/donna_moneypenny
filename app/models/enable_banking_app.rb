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
  normalizes :private_key, with: ->(key) { normalize_pem(key) }

  validates :application_id, uniqueness: true, allow_nil: true
  validates :application_id, :private_key, presence: true, on: :credentials
  validate :private_key_is_an_rsa_private_key, if: :private_key?

  # Rebuilds a pasted PEM key in its standard layout: whatever indentation, tabs, wrapping or
  # line endings it picked up on the way (YAML, a terminal, an editor), the base64 body has no
  # whitespace of its own. Text that isn't PEM is kept, for the validation to report.
  def self.normalize_pem(text)
    text = text.to_s.strip
    match = text.match(/-----\s*BEGIN\s+([A-Z][A-Z\s]*?)\s*-----(.*?)-----\s*END\s+[A-Z\s]*?-----/m)
    return text.presence unless match

    label = match[1].split.join(" ")
    body = match[2].gsub(/\s+/, "")
    "-----BEGIN #{label}-----\n#{body.scan(/.{1,64}/).join("\n")}\n-----END #{label}-----\n"
  end

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
