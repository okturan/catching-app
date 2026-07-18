Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords"
  }

  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"
  resource :dashboard, only: :show

  resources :events, only: %i[show new create update] do
    resources :activities, only: %i[index show new create]
    resources :time_slots, only: :create
  end
end
