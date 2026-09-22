# A length of time in whole minutes, printed the way the pages print it:
# "1 h 30 min", "2 h", "45 min". Never a clock reading, so never a zone.
Length = Data.define(:minutes) do
  def to_s
    hours, rest = minutes.divmod(60)
    [ ("#{hours} h" if hours.positive?), ("#{rest} min" if rest.positive?) ].compact.join(" ")
  end
end
