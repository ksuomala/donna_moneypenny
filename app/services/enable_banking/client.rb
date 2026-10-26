require "net/http"
require "openssl"
require "jwt"

module EnableBanking
  class Client
    BASE_URL = "https://api.enablebanking.com"
    JWT_TTL = 3600

    Error = Class.new(StandardError)

    # Every user has their own Enable Banking application (EnableBankingApp); the app's key signs
    # the requests. Callers get their client through Client.for so tests can swap in a fake.
    class_attribute :factory, default: ->(app) { new(application_id: app&.application_id, private_key: app&.private_key) }

    def self.for(app)
      factory.call(app)
    end

    def initialize(application_id:, private_key:)
      raise Error, "Enable Banking credentials are not configured" if application_id.blank? || private_key.blank?

      @application_id = application_id
      @private_key = OpenSSL::PKey::RSA.new(private_key)
    end

    # Banks (ASPSPs) available in a country, including each one's maximum consent validity.
    def aspsps(country:)
      get("/aspsps", country: country).fetch("aspsps")
    end

    # Starts a bank authorization. Returns the bank's URL to send the user to; the bank
    # redirects back to redirect_url with ?code=...&state=... once the user has approved.
    def start_authorization(aspsp_name:, country:, redirect_url:, state:, valid_until:, psu_type: "personal")
      post("/auth",
        access: { valid_until: valid_until.utc.iso8601 },
        aspsp: { name: aspsp_name, country: country },
        state: state,
        redirect_url: redirect_url,
        psu_type: psu_type)
    end

    # Exchanges the authorization code returned on the redirect/callback URL
    # for a session containing the list of accounts the user authorized access to.
    def create_session(code:)
      post("/sessions", code: code)
    end

    # One page of an account's transactions; follow "continuation_key" for the next page.
    def transactions(account_uid:, date_from:, continuation_key: nil)
      params = { date_from: date_from.iso8601 }
      params[:continuation_key] = continuation_key if continuation_key
      get("/accounts/#{account_uid}/transactions", params)
    end

    # The account's current balances (booked, available, …), as the bank reports them.
    def balances(account_uid:)
      get("/accounts/#{account_uid}/balances").fetch("balances")
    end

    private

    def get(path, params = {})
      uri = URI.join(BASE_URL, path)
      uri.query = URI.encode_www_form(params) if params.any?

      request(Net::HTTP::Get.new(uri))
    end

    def post(path, body)
      request = Net::HTTP::Post.new(URI.join(BASE_URL, path))
      request["Content-Type"] = "application/json"
      request.body = body.to_json

      request(request)
    end

    def request(request)
      request["Authorization"] = "Bearer #{access_token}"
      uri = request.uri

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "Enable Banking request to #{uri.path} failed (#{response.code}): #{response.body}"
      end

      JSON.parse(response.body)
    end

    def access_token
      now = Time.now.to_i
      payload = { iss: "enablebanking.com", aud: "api.enablebanking.com", iat: now, exp: now + JWT_TTL }

      JWT.encode(payload, @private_key, "RS256", { kid: @application_id })
    end
  end
end
