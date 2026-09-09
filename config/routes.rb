Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # The public site's screenings listing (with filter form).
  resources :screenings, only: :index

  # The mock external festival-management API. Treat this as a third party.
  namespace :mock_api do
    resources :screenings, only: :index
  end

  # Sidekiq's web dashboard, handy for watching the sync job run.
  require "sidekiq/web"
  mount Sidekiq::Web => "/sidekiq"

  # Defines the root path route ("/")
  root "screenings#index"
end
