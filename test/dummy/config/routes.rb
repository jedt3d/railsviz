Rails.application.routes.draw do
  get "/health", to: "health#show"           # controller does not exist (Review Focus)
  resources :patients, only: %i[index show] do
    get :export, on: :member
  end
  mount Blog::Engine => "/blog"
end
