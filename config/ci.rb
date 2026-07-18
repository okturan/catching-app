# Run locally with bin/ci.

CI.run do
  step "Setup", "env CI=true RAILS_ENV=test bin/setup --skip-server"
  step "Style: Ruby", "bin/rubocop"

  step "Security: Gem audit", "bin/bundler-audit check --update"
  step "Security: JavaScript audit", "npm audit --audit-level=high"
  step "Security: Brakeman", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"

  step "Code loading", "env RAILS_ENV=test bin/rails zeitwerk:check"
  step "Assets", "npm run check"
  step "Tests: Rails", "bin/rails test"
  step "Tests: System", "bin/rails test:system"
end
