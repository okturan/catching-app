Rails.application.routes.draw do
  # www.<APP_HOST> answers with a permanent redirect to the bare domain.
  constraints ->(request) { ENV["APP_HOST"].present? && request.host == "www.#{ENV["APP_HOST"]}" } do
    get "(*path)", to: redirect(status: 301) { |_params, request| "https://#{ENV["APP_HOST"]}#{request.fullpath}" }, format: false
  end

  get "calendar/:token" => "calendar_links#show", as: :calendar_link, constraints: { token: %r{[^/]+} }, format: false
    resource :session, only: %i[new create destroy]
  resources :passwords, param: :token, only: %i[new create edit update]
  resource :registration, only: %i[new create]
  resource :account, only: %i[edit update destroy]

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
  resource :dashboard, only: :show

  get "events/pending", to: "events#pending", as: :pending_events
  resources :events, only: %i[new create]
  resources :organizer_links, only: %i[new create]

  # One address per participant, /p/:key. The key is the token of an
  # emailed link, or behind a session the participant's id. Nested ids name
  # a guest the organizer acts on, or an item of the plan.
  scope "p/:key", constraints: { key: %r{[^/]+} }, format: false do
    resource :participant, path: "", only: %i[show update destroy] do
      scope module: :participants do
        resource :decline, only: :create
        resource :finalization, only: :create
        resources :invitations, only: :create
        resources :guests, only: :destroy do
          resource :resend, only: :create
          resource :link_reveal, only: :create
        end
        resource :details, only: %i[edit update]
        resource :offer, only: %i[edit update]
        resource :notice, only: :create
        resource :cancellation, only: :create
        resource :reopening, only: :create
        resource :calendar, only: :show, path: "calendar.ics"
        resources :plan_items, path: "plan", only: %i[create update destroy] do
          resource :move, only: :create, controller: :plan_item_moves
        end
        resource :claim, only: %i[show create]
      end
    end
  end
end
