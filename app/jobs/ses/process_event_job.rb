module Ses
  class ProcessEventJob < ApplicationJob
    queue_as :default

    def perform(message)
      payload = JSON.parse(message)
      EventRecorder.new(payload).call if payload.is_a?(Hash)
    rescue JSON::ParserError
      Rails.logger.warn('[Ses::ProcessEventJob] mensagem inválida')
    end
  end
end
