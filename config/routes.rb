Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords"
  }

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
  resource :dashboard, only: :show

  get "events/pending", to: "events#pending", as: :pending_events
  resources :events, only: %i[new create]
  resources :organizer_links, only: %i[new create]

  # Actions shared by the token family (/p/:token) and the session family
  # (/participations/:participation_id). The viewer is always the scope
  # parameter; nested ids name a target guest.
  concern :participation_actions do
    scope module: :participations do
      resource :decline, only: :create
      resource :finalization, only: :create
      resources :invitations, only: :create
      resources :participants, only: :destroy do
        resource :resend, only: :create
        resource :link_reveal, only: :create
      end
      resource :details, only: %i[edit update] # organizer
      resource :offer, only: %i[edit update] # organizer, while open: Change the times
      resource :notice, only: :create # organizer: Tell the guests
      resource :cancellation, only: :create # organizer: terminal, read-only afterwards
      resource :calendar, only: :show, path: "calendar.ics", format: false # any participant, finalized
      resources :activities, only: %i[create update destroy] do # organizer: the plan
        resource :move, only: :create, controller: :activity_moves # organizer: move[position]
      end
    end
  end

  scope "p/:token", constraints: { token: %r{[^/]+} }, format: false do
    resource :participation, path: "", only: %i[show update destroy] do
      concerns :participation_actions
      scope module: :participations do
        resource :claim, only: %i[show create]
      end
    end
  end

  scope "participations/:participation_id", as: :my do
    resource :participation, path: "", only: %i[show update destroy] do
      concerns :participation_actions
    end
  end
end
