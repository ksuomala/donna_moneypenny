# One Enable Banking session: the consent given at a bank, valid until valid_until.
# Reconnecting (e.g. after the consent expires) creates a new connection; accounts are
# matched by IBAN so they carry over to the newest connection.
class BankConnection < ApplicationRecord
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
    record = (identification_hash && BankAccount.find_by(identification_hash: identification_hash)) ||
      (iban && BankAccount.find_by(iban: iban)) ||
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
