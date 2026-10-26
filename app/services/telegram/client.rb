require "net/http"

module Telegram
  # Sends messages through the Telegram Bot API (https://core.telegram.org/bots/api#sendmessage).
  # The token can be any bot's, also one another program polls for updates: sending doesn't
  # conflict with receiving. Messages are HTML (Telegram's small subset: b, i, code, a).
  class Client
    BASE_URL = "https://api.telegram.org/"

    Error = Class.new(StandardError)

    # Callers get their client through Client.for so tests can swap in a fake.
    class_attribute :factory, default: -> { new }

    def self.for = factory.call
    def self.bot_token = Rails.application.credentials.dig(:telegram, :bot_token).presence || ENV["TELEGRAM_BOT_TOKEN"].presence
    def self.configured? = bot_token.present?

    def initialize(token: self.class.bot_token)
      @token = token
    end

    # Returns the sent message as Telegram describes it.
    def send_message(chat_id:, text:)
      raise Error, "No Telegram bot token: add telegram: bot_token: with bin/rails credentials:edit, or set TELEGRAM_BOT_TOKEN" if @token.blank?

      body = { chat_id: chat_id, text: text, parse_mode: "HTML", disable_web_page_preview: true }.to_json
      response = Net::HTTP.post(endpoint("sendMessage"), body, "Content-Type" => "application/json")
      raise Error, "Telegram sendMessage to chat #{chat_id} failed (#{response.code}): #{response.body.to_s.first(300)}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body).fetch("result")
    rescue JSON::ParserError, KeyError => e
      raise Error, "Unexpected Telegram response: #{e.message}"
    end

    # A bot token has a colon in it ("123456:ABC-def"), so it is never joined onto the base URL
    # as a relative path: URI.join would read everything before the colon as a scheme.
    def endpoint(method) = URI.parse("#{BASE_URL}bot#{@token}/#{method}")
  end
end
