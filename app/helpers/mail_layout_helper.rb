# The pieces every mail is built from, with the styles inline: mail clients
# drop stylesheets. The palette is the site's: wall, glass, ink, enamel.
module MailLayoutHelper
  INK = "#141414".freeze
  INK_SOFT = "#4a4744".freeze
  WALL = "#f2efe9".freeze
  ENAMEL = "#24405e".freeze
  AWAKE = "#ffc65a".freeze
  BODY_FONT = "'Helvetica Neue', Helvetica, Arial, sans-serif".freeze
  TIME_FONT = "Menlo, Consolas, 'Courier New', monospace".freeze

  def email_heading(text)
    tag.h1(text, style: "margin: 0 0 16px; font-family: #{BODY_FONT}; font-size: 24px; line-height: 1.25; font-weight: 800; " \
      "letter-spacing: -0.02em; color: #{INK};")
  end

  def email_paragraph(content = nil, &)
    tag.p(content || capture(&), style: "margin: 0 0 16px; font-family: #{BODY_FONT}; font-size: 16px; line-height: 1.55; color: #{INK};")
  end

  def email_note(content = nil, &)
    tag.p(content || capture(&), style: "margin: 0 0 12px; font-family: #{BODY_FONT}; font-size: 14px; line-height: 1.5; color: #{INK_SOFT};")
  end

  # A time read off the wall: the mono face on a band of wall colour.
  def email_times(*lines)
    rows = safe_join(lines.compact.map.with_index do |line, index|
      tag.div(line, style: index.zero? ? "font-size: 16px; color: #{INK};" : "margin-top: 4px; font-size: 13px; color: #{INK_SOFT};")
    end)
    tag.div(rows, style: "margin: 0 0 20px; padding: 14px 16px; background: #{WALL}; border-radius: 4px; " \
      "font-family: #{TIME_FONT}; line-height: 1.45;")
  end

  # The enamel plate as a bulletproof button, with the plain link under it
  # for clients that show no buttons.
  def email_button(label, url, fallback: true)
    button = tag.table(role: "presentation", cellpadding: 0, cellspacing: 0, border: 0, style: "margin: 4px 0 #{fallback ? 10 : 20}px;") do
      tag.tr do
        tag.td(bgcolor: ENAMEL, style: "border-radius: 3px; background: #{ENAMEL};") do
          link_to(label, url, style: "display: inline-block; padding: 14px 26px; font-family: #{BODY_FONT}; font-size: 13px; " \
            "font-weight: 700; letter-spacing: 0.12em; text-transform: uppercase; color: #ffffff; text-decoration: none; border-radius: 3px;")
        end
      end
    end
    return button unless fallback

    button + tag.p(style: "margin: 0 0 20px; font-family: #{BODY_FONT}; font-size: 12px; line-height: 1.5; color: #{INK_SOFT}; word-break: break-all;") do
      safe_join([ "Or open this link: ", link_to(url, url, style: "color: #{ENAMEL};") ])
    end
  end

  # Label and value lines: Where, How long.
  def email_facts(facts)
    safe_join(facts.compact_blank.map do |label, value|
      tag.p(style: "margin: 0 0 6px; font-family: #{BODY_FONT}; font-size: 15px; line-height: 1.5; color: #{INK};") do
        safe_join([ tag.strong(label), " ", value ])
      end
    end) + (facts.compact_blank.any? ? tag.div(style: "height: 14px; line-height: 14px; font-size: 1px;") { "&nbsp;".html_safe } : "".html_safe)
  end

  def email_list(items)
    tag.ol(safe_join(items.map { tag.li(it, style: "margin: 0 0 6px;") }),
      style: "margin: 0 0 20px; padding-left: 22px; font-family: #{BODY_FONT}; font-size: 15px; line-height: 1.5; color: #{INK};")
  end

  def email_rule
    tag.div(style: "height: 1px; margin: 8px 0 20px; background: #e4dfd5; line-height: 1px; font-size: 1px;") { "&nbsp;".html_safe }
  end
end
