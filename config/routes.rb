require "sidekiq/web"

Rails.application.routes.draw do
  namespace :api do
    resources :productions, only: %i[index show], param: :slug
    get "theaters/:theater_slug/productions/:slug", to: "productions#show", as: :theater_production
    resources :theaters,    only: %i[index show], param: :slug
    resources :directors,   only: %i[index show], param: :slug
    resources :reviews,     only: %i[index]
    resources :screenings,  only: %i[index]
    resources :ratings,     only: %i[create]
    resources :comments,    only: %i[create destroy]

    scope :home, controller: :home, as: :home do
      get :top_rated
      get :upcoming_premieres
      get :latest_reviews
      get :city_stats
    end

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
