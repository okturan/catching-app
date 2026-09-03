# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=4.0.5
ARG NODE_VERSION=24.18.0

FROM docker.io/library/node:${NODE_VERSION}-bookworm-slim AS node
FROM docker.io/library/ruby:${RUBY_VERSION}-slim-bookworm AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 postgresql-client tzdata && \
    ln -s "/usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2" /usr/local/lib/libjemalloc.so.2 && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    NODE_ENV="production" \
    LOG_REQUESTS="false" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so.2"

FROM base AS build

ARG BUNDLER_VERSION=4.0.15
ARG NPM_VERSION=11.16.0
ENV NODE_ENV="development"

COPY --from=node /usr/local/ /usr/local/

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives && \
    gem install bundler --version "${BUNDLER_VERSION}" --no-document

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY package.json package-lock.json .npmrc ./
RUN test "$(npm --version)" = "${NPM_VERSION}" && npm ci --include=dev

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/ && \
    SECRET_KEY_BASE_DUMMY=1 \
      APP_HOST=example.com \
      MAILER_FROM=no-reply@example.invalid \
      SMTP_ADDRESS=localhost \
      DATABASE_URL=postgresql://postgres:postgres@localhost/catching_app_production \
      bin/rails assets:precompile && \
    rm -rf node_modules

FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    mkdir -p log storage tmp && \
    chown -R rails:rails log storage tmp

USER 1000:1000

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
  CMD curl --fail --silent http://127.0.0.1/up || exit 1

CMD ["./bin/thrust", "./bin/rails", "server"]
