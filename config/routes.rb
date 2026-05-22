Rails.application.routes.draw do
  namespace :api do
    resources :productions, only: %i[index show], param: :slug
  end
end
