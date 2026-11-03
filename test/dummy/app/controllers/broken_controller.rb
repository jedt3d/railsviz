# Fixture for rails_vis: lists an action with no method, so the collector's per-action rescue is exercised.
class BrokenController < ApplicationController
  def self.action_methods = super | Set["ghost"]
  def index = head(:ok)
end
