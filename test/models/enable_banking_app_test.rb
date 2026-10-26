require "test_helper"

class EnableBankingAppTest < ActiveSupport::TestCase
  test "a pasted key is rebuilt in the standard PEM layout" do
    begin_line, *body, end_line = ENABLE_BANKING_TEST_KEY.lines.map(&:strip)
    messy = "  #{begin_line}\r\n\t#{body.join.scan(/.{1,40}/).join("\n    \t")}  \r\n    #{end_line}\n\n"

    app = EnableBankingApp.new(user: users(:one), application_id: "app-1", private_key: messy)

    assert_equal ENABLE_BANKING_TEST_KEY, app.private_key
    assert app.valid?(:credentials)
  end

  test "a key squashed onto one line is unwrapped too" do
    app = EnableBankingApp.new(user: users(:one), private_key: ENABLE_BANKING_TEST_KEY.tr("\n", " "))

    assert_equal ENABLE_BANKING_TEST_KEY, app.private_key
  end

  test "text that is not a key fails the validation" do
    app = EnableBankingApp.new(user: users(:one), application_id: "app-1", private_key: "  not a key  ")

    assert_not app.valid?(:credentials)
    assert_includes app.errors[:private_key], "is not a PEM-encoded RSA private key"
  end
end
