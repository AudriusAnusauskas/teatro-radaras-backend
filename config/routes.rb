Rails.application.routes.draw do
  namespace :api do
    resources :productions, only: %i[index show], param: :slug
    resources :theaters,    only: %i[index show], param: :slug
    resources :directors,   only: %i[index show], param: :slug
    resources :reviews,     only: %i[index]

    get "search", to: "search#index"
  end
end
