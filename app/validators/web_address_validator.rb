# An http(s) address with a host and no userinfo: the shape the database
# check on events pins.
class WebAddressValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    uri = URI.parse(value)
    record.errors.add(attribute, :not_a_web_address) unless uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
  rescue URI::InvalidURIError
    record.errors.add(attribute, :not_a_web_address)
  end
end
