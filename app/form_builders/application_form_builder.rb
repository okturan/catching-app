# Every field one way: label, control, error and hint, tied together with
# aria-describedby so assistive technology reads them as one.
class ApplicationFormBuilder < ActionView::Helpers::FormBuilder
  # form.field :name, required: true, hint: "Your friends see this."
  # form.field :description, as: :text_area, optional: true, rows: 3
  # form.field :duration_minutes, as: :select, choices: options, include_blank: "Not set"
  #
  # describedby names one more element, such as a note a block adds.
  def field(attribute, as: :text_field, label: nil, optional: false, hint: nil, describedby: nil, choices: nil, include_blank: nil, **html, &extra)
    name = label || @object.class.human_attribute_name(attribute)
    error = error_message(attribute, name)
    # After a failed submit the summary takes focus; no field claims it.
    html.delete(:autofocus) if failed?
    html[:class] = @template.class_names(as == :select ? "form-select" : "form-control", "is-invalid": error)
    html[:aria] = { invalid: (true if error),
      describedby: [ (field_id(attribute, :help) if hint), describedby, (field_id(attribute, :error) if error) ].compact.join(" ").presence }

    @template.tag.div(class: "mb-3") do
      @template.safe_join([
        label(attribute, optional ? "#{name} (optional)" : name, class: "form-label"),
        as == :select ? select(attribute, choices, { include_blank: }, html) : public_send(as, attribute, html),
        (@template.tag.div(error, class: "invalid-feedback", id: field_id(attribute, :error)) if error),
        (@template.tag.p(hint, class: "form-text", id: field_id(attribute, :help)) if hint),
        (@template.capture(&extra) if extra)
      ])
    end
  end

  # Every item links to the control it is about.
  def error_summary(links = @object.errors.map { [ it.full_message, field_id(it.attribute) ] })
    return if links.empty?

    @template.tag.div(class: "error-summary", role: "alert", tabindex: -1, id: "error-summary", data: { controller: "error-summary" }) do
      @template.tag.h2("There is a problem") +
        @template.tag.ul { @template.safe_join(links.map { |message, target| @template.tag.li(@template.link_to(message, "##{target}")) }) }
    end
  end

  private

  # A form without a model, such as a lookup by address, never fails here.
  def failed?
    @object.present? && @object.errors.any?
  end

  def error_message(attribute, name)
    @object.errors.messages_for(attribute).map { "#{name} #{it}" }.to_sentence.presence if failed?
  end
end
