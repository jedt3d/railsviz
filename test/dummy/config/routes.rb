Rails.application.routes.draw do
  get "/health", to: "health#show"           # controller does not exist (Review Focus)
  get "/old-patients", to: redirect("/patients")                                  # redirect rows (issue 25)
  get "/legacy/:id", to: redirect { |params, _req| "/patients/#{params[:id]}" }
  get "/elsewhere", to: redirect(host: "example.com")
  resources :patients, only: %i[index show] do
    get :export, on: :member
  end
  get "/admin", to: "admin#index"
  get "/admin/reports", to: "admin/reports#index"
  mount Blog::Engine => "/blog"
end
