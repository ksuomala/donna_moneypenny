# One Enable Banking session: the consent given at a bank, valid until valid_until.
# Reconnecting (e.g. after the consent expires) creates a new connection; accounts are
# matched by IBAN so they carry over to the user's newest connection.
class BankConnection < ApplicationRecord
  include OwnedByUser

  # The app whose key signs every request on this connection's session and accounts.
  belongs_to :enable_banking_app, optional: true
  has_many :bank_accounts, dependent: :restrict_with_error

  enum :status, { active: 0, expired: 1, revoked: 2 }

  validates :session_id, :aspsp_name, :aspsp_country, :valid_until, presence: true

  # Persists the response of POST /sessions (EnableBanking::Client#create_session).
  def self.record_session!(data)
    transaction do
      connection = create!(
        session_id: data.fetch("session_id"),
        aspsp_name: data.dig("aspsp", "name"),
        aspsp_country: data.dig("aspsp", "country"),
        valid_until: data.dig("access", "valid_until"),
        raw: data
      )

      Array(data["accounts"]).each { |account| connection.attach_account!(account) }
      connection
    end
  end

  def attach_account!(account)
    # Older API versions list accounts as bare uid strings.
    account = { "uid" => account } if account.is_a?(String)
    iban = account.dig("account_id", "iban")
    identification_hash = account["identification_hash"]

    # identification_hash is Enable Banking's stable account identity across sessions;
    # IBAN is the fallback (cards have no IBAN, so they rely on the hash).
    # Only this user's accounts carry over: another user's login to the same account gets its own.
    own = BankAccount.owned_by(user_id)
    record = (identification_hash && own.find_by(identification_hash: identification_hash)) ||
      (iban && own.find_by(iban: iban)) ||
      BankAccount.new
    record.update!(
      bank_connection: self,
      type: BankAccount.type_from_api(account),
      uid: account.fetch("uid"),
      identification_hash: identification_hash,
      iban: iban,
      # Nordea puts the account holder in "name" and the account type in "product".
      name: account["product"].presence || account["name"],
      currency: account["currency"],
      raw: account
    )
  end

  def usable?
    active? && valid_until.future?
  end
end
