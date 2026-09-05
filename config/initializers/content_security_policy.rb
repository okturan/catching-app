Rails.application.config.content_security_policy do |policy|
  policy.default_src :self
  policy.base_uri :self
  policy.connect_src :self
  policy.font_src :self, :data
  policy.form_action :self
  policy.frame_ancestors :none
  policy.img_src :self, :data
  policy.media_src :self
  policy.object_src :none
  policy.script_src :self
  policy.style_src :self, :unsafe_inline
end
