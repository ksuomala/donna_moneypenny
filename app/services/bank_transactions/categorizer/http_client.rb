require "net/http"

module BankTransactions
  class Categorizer
    # A JSON-over-HTTPS client for the providers without a Ruby SDK (OpenAI, TypeSafe). Retries
    # timeouts and server errors twice; a 429 raises RateLimited so the job can wait.
    class HttpClient
      RETRIES = 2

      def initialize(url:, api_key:, headers: {}, timeout: 600)
        @uri = URI(url)
        @headers = { "Authorization" => "Bearer #{api_key}", "Content-Type" => "application/json" }.merge(headers)
        @timeout = timeout
      end

      def post(body)
        attempts = 0
        begin
          attempts += 1
          request = Net::HTTP::Post.new(@uri)
          @headers.each { |name, value| request[name] = value }
          request.body = body.to_json
          response = Net::HTTP.start(@uri.hostname, @uri.port, use_ssl: true, open_timeout: 30, read_timeout: @timeout) { |http| http.request(request) }
          raise RateLimited, "#{@uri.host} rate limited the request" if response.code == "429"
          raise Retryable, "#{@uri.host} answered #{response.code}" if response.code.start_with?("5")
          raise Error, "#{@uri.host} answered #{response.code}: #{response.body.to_s.first(300)}" unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        rescue Retryable, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET => e
          retry if attempts <= RETRIES
          raise Error, "#{@uri.host} failed after #{attempts} attempts: #{e.message}"
        end
      end

      Retryable = Class.new(StandardError)
    end
  end
end
