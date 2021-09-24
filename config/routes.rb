Rails.application.routes.draw do
  devise_for :users
  root to: 'pages#home'
  resources :activities, only: [ :index, :show, :new, :create ] do
    resources :events, only: [ :new, :create, :show]
  end
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

  resources :events, only: [ :index, :show, :new, :create, :edit, :update ]
  resources :time_slots, only: [ :new, :create ]
  resource :dashboard, only: :show
end
