# An IANA zone name ActiveSupport knows, such as "Europe/Berlin".
class TimeZoneValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    record.errors.add(attribute, :unknown_time_zone) unless value.present? && ActiveSupport::TimeZone[value]
  end
end
