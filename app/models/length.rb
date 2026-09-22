# "1 h 30 min", "2 h", "45 min": a length, never a clock reading.
Length = Data.define(:minutes) do
  def to_s
    hours, rest = minutes.divmod(60)
    [ ("#{hours} h" if hours.positive?), ("#{rest} min" if rest.positive?) ].compact.join(" ")
  end
end
