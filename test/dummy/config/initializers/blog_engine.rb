module Blog
  class Engine < ::Rails::Engine
    isolate_namespace Blog
  end
end
Blog::Engine.routes.draw { get "/posts", to: "posts#index" }
