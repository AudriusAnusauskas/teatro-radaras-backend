require "sidekiq/web"

Rails.application.routes.draw do
  namespace :api do
    resources :productions, only: %i[index show], param: :slug
    resources :theaters,    only: %i[index show], param: :slug
    resources :directors,   only: %i[index show], param: :slug
    resources :reviews,     only: %i[index]
    resources :ratings,     only: %i[create]
    resources :comments,    only: %i[create destroy]

    get "search", to: "search#index"
  end

  devise_for :users,
           controllers: { omniauth_callbacks: "users/omniauth_callbacks" },
           skip: [:sessions, :registrations, :passwords]

  devise_scope :user do
    delete "users/sign_out", to: "users/sessions#destroy"
  end

  namespace :api do
    get "me", to: "sessions#show"
  end

  if Rails.env.development?
    mount Sidekiq::Web => "/sidekiq"
  end
end
