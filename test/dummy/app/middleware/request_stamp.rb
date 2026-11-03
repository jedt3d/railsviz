# Fixture for rails_vis: a middleware the app inserts itself (Middleware view shows gem: null and the app source line).
class RequestStamp
  def initialize(app) = @app = app
  def call(env) = @app.call(env)
end
