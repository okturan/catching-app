# The shapes a moment takes on the pages and in mail, beside Rails' own :time
# ("20:00"). to_fs prints in the zone it is handed and converts nothing.
Time::DATE_FORMATS[:day] = "%a %-d %b"                # Tue 15 Jan
Time::DATE_FORMATS[:date_time] = "%a %-d %b %Y %H:%M" # Tue 15 Jan 2030 20:00
