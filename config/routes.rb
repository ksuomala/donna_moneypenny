Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Public legal pages, linked from the Enable Banking application registration
  get "privacy" => "legal#privacy", as: :privacy
  get "terms" => "legal#terms", as: :terms

  namespace :enable_banking do
    # The signed-in user's own Enable Banking application
    resource :app, only: %i[show update]
    resource :authorization, only: :create
    # Each app's own callback, whitelisted as that app's redirect URL in the Enable Banking Control Panel
    get "sessions/:token", to: "sessions#create", as: :callback
  end

  # Sign in and out. Users are created with bin/rails users:create; there is no sign-up page.
  resource :session, only: %i[new create destroy]

  resource :stats, only: :show

  root "bank_connections#index"
end
