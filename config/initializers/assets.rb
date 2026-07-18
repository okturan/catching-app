Rails.application.config.assets.version = "2.0"
Rails.application.config.assets.paths << Rails.root.join("app/assets/builds")
Rails.application.config.assets.excluded_paths << Rails.root.join("app/assets/stylesheets")

# Turbo is bundled by esbuild and this application does not use Rails UJS, so
# do not publish redundant standalone copies from their gem asset paths.
%w[actionview turbo-rails].each do |gem_name|
  gem_root = Gem.loaded_specs.fetch(gem_name).full_gem_path
  Rails.application.config.assets.excluded_paths << File.join(gem_root, "app/assets/javascripts")
end
