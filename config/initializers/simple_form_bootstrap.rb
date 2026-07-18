# frozen_string_literal: true

# Bootstrap 5 wrappers for Simple Form.
SimpleForm.setup do |config|
  config.button_class = "btn"
  config.boolean_label_class = "form-check-label"
  config.boolean_style = :inline
  config.item_wrapper_tag = :div
  config.include_default_input_wrapper_class = false
  config.error_notification_class = "alert alert-danger"
  config.error_method = :to_sentence
  config.input_field_error_class = "is-invalid"
  config.input_field_valid_class = "is-valid"

  config.wrappers :vertical_form, class: "mb-3" do |builder|
    builder.use :html5
    builder.use :placeholder
    builder.optional :maxlength
    builder.optional :minlength
    builder.optional :pattern
    builder.optional :min_max
    builder.optional :readonly
    builder.use :label, class: "form-label"
    builder.use :input, class: "form-control", error_class: "is-invalid", valid_class: "is-valid"
    builder.use :full_error, wrap_with: { class: "invalid-feedback" }
    builder.use :hint, wrap_with: { class: "form-text" }
  end

  config.wrappers :vertical_boolean, tag: "fieldset", class: "mb-3" do |builder|
    builder.use :html5
    builder.optional :readonly
    builder.wrapper :form_check_wrapper, class: "form-check" do |wrapper|
      wrapper.use :input, class: "form-check-input", error_class: "is-invalid", valid_class: "is-valid"
      wrapper.use :label, class: "form-check-label"
      wrapper.use :full_error, wrap_with: { class: "invalid-feedback" }
      wrapper.use :hint, wrap_with: { class: "form-text" }
    end
  end

  config.wrappers :vertical_collection,
    item_wrapper_class: "form-check",
    item_label_class: "form-check-label",
    tag: "fieldset",
    class: "mb-3" do |builder|
    builder.use :html5
    builder.optional :readonly
    builder.wrapper :legend_tag, tag: "legend", class: "col-form-label pt-0" do |legend|
      legend.use :label_text
    end
    builder.use :input, class: "form-check-input", error_class: "is-invalid", valid_class: "is-valid"
    builder.use :full_error, wrap_with: { class: "invalid-feedback d-block" }
    builder.use :hint, wrap_with: { class: "form-text" }
  end

  config.wrappers :vertical_multi_select, tag: "fieldset", class: "mb-3" do |builder|
    builder.use :html5
    builder.optional :readonly
    builder.use :label, class: "form-label"
    builder.use :input, class: "form-select", error_class: "is-invalid", valid_class: "is-valid"
    builder.use :full_error, wrap_with: { class: "invalid-feedback d-block" }
    builder.use :hint, wrap_with: { class: "form-text" }
  end

  config.default_wrapper = :vertical_form
  config.wrapper_mappings = {
    boolean: :vertical_boolean,
    check_boxes: :vertical_collection,
    date: :vertical_multi_select,
    datetime: :vertical_multi_select,
    radio_buttons: :vertical_collection,
    time: :vertical_multi_select
  }
end
