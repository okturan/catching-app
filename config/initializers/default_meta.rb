DEFAULT_META = YAML.safe_load_file(
  Rails.root.join("config/meta.yml"),
  permitted_classes: [],
  aliases: false
).with_indifferent_access.freeze
