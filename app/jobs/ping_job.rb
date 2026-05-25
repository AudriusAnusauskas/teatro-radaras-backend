class PingJob < ApplicationJob
  queue_as :default

  def perform(message = "pong")
    Rails.logger.info("[PingJob] received: #{message} at #{Time.current.iso8601}")
  end
end
