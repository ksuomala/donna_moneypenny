module EnableBanking
  # A bank offered on the bank connections page, by the name and country Enable Banking lists
  # it under (GET /aspsps). The key is what the connect button posts.
  class Bank < Data.define(:key, :name, :country)
    ALL = [
      new(key: "nordea", name: "Nordea", country: "FI"),
      new(key: "revolut", name: "Revolut", country: "LT"),
      new(key: "danske", name: "Danske Bank", country: "DK")
    ].freeze

    def self.all = ALL
    def self.find(key) = ALL.find { |bank| bank.key == key.to_s }
  end
end
