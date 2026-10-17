module EnableBanking
  # Records calls and returns canned Enable Banking responses.
  class FakeClient
    attr_reader :calls

    def initialize(session_data: nil, error: nil)
      @session_data = session_data
      @error = error
      @calls = []
    end

    def aspsps(country:)
      @calls << [ :aspsps, country ]
      [ { "name" => "Nordea", "country" => "FI", "maximum_consent_validity" => 15_552_000 } ]
    end

    def start_authorization(**args)
      @calls << [ :start_authorization, args ]
      raise @error if @error

      { "url" => "https://bank.example/authorize?id=123", "authorization_id" => "auth-123" }
    end

    def create_session(code:)
      @calls << [ :create_session, code ]
      raise @error if @error

      @session_data
    end
  end
end
