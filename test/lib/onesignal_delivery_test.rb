require "test_helper"
require "mail"

class OnesignalDeliveryTest < ActiveSupport::TestCase
  FakeResponse = Struct.new(:code, :body, :success) do
    def is_a?(klass) = klass == Net::HTTPSuccess ? success : super
  end

  setup do
    @sent = []
    @mail = ::Mail.new do
      from "Catching App <no-reply@catching.app>"
      to "guest@example.com"
      reply_to "owner@example.com"
      subject "Catching App: you are invited"
      text_part { body "Open http://example.com/p/abc" }
      html_part { content_type "text/html; charset=UTF-8"; body "<p><a href=\"http://example.com/p/abc\">link</a></p>" }
    end
  end

  test "each recipient is one request with the html body, click tracking off and unsubscribes included" do
    with_http(FakeResponse.new("200", { id: "n1" }.to_json, true)) { @delivery.deliver!(@mail) }

    assert_equal 1, @sent.size
    request = @sent.first
    assert_equal "Key key-1", request["Authorization"]
    body = JSON.parse(request.body)
    assert_equal "app-1", body["app_id"]
    assert_equal [ "guest@example.com" ], body["email_to"]
    assert_equal "Catching App: you are invited", body["email_subject"]
    assert_includes body["email_body"], %(href="http://example.com/p/abc")
    assert_equal [ "no-reply@catching.app", "Catching App", "owner@example.com" ],
      body.values_at("email_from_address", "email_from_name", "email_reply_to_address")
    assert_equal true, body["disable_email_click_tracking"]
    assert_equal true, body["include_unsubscribed"]
  end

  test "a refusal raises, so the delivery job retries and the ledger records the failure" do
    error = assert_raises(OnesignalDelivery::Error) do
      with_http(FakeResponse.new("400", { errors: [ "Invalid email" ] }.to_json, false)) { @delivery.deliver!(@mail) }
    end
    assert_includes error.message, "Invalid email"

    assert_raises(OnesignalDelivery::Error) do
      with_http(FakeResponse.new("200", { errors: [ "All included players are not subscribed" ] }.to_json, true)) { @delivery.deliver!(@mail) }
    end
  end

  private

  def with_http(response)
    sent = @sent
    @delivery = OnesignalDelivery.new(app_id: "app-1", api_key: "key-1", transport: ->(request) { sent << request; response })
    yield
  end
end
