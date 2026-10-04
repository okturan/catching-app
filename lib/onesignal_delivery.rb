require "net/http"
require "json"

# Action Mailer delivery through OneSignal's email API, one request per
# recipient. OneSignal sends no attachments, so mails link to their files.
# Click tracking stays off: it would rewrite every capability link to a
# tracking host. Transactional mail goes to every address, unsubscribed or not.
class OnesignalDelivery
  ENDPOINT = URI("https://api.onesignal.com/notifications?c=email")

  class Error < StandardError; end

  attr_reader :settings

  def initialize(settings)
    @settings = settings
  end

  def deliver!(mail)
    from = mail[:from].addrs.first
    Array(mail.to).each do |to|
      post(
        app_id: settings.fetch(:app_id),
        email_to: [ to ],
        email_subject: mail.subject,
        email_body: html_of(mail),
        email_from_address: from.address,
        email_from_name: from.display_name,
        email_reply_to_address: Array(mail.reply_to).first,
        include_unsubscribed: true,
        disable_email_click_tracking: true
      )
    end
  end

  private

  # settings[:transport] stands in for the network in tests.
  def transport
    settings[:transport] || lambda do |request|
      Net::HTTP.start(ENDPOINT.host, ENDPOINT.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { it.request(request) }
    end
  end

  def html_of(mail)
    (mail.html_part || mail).decoded
  end

  def post(payload)
    request = Net::HTTP::Post.new(ENDPOINT, "Content-Type" => "application/json", "Authorization" => "Key #{settings.fetch(:api_key)}")
    request.body = payload.compact.to_json
    response = transport.call(request)
    body = JSON.parse(response.body.presence || "{}") rescue {}
    return body if response.is_a?(Net::HTTPSuccess) && body["errors"].blank?

    raise Error, "OneSignal refused the mail (#{response.code}): #{body["errors"] || response.body.to_s.truncate(200)}"
  end
end
