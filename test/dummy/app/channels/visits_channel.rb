class VisitsChannel < ApplicationCable::Channel
  def subscribed = stream_from("visits")
end
