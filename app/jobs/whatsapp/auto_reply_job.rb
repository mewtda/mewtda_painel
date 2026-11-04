module Whatsapp
  # Resposta automática (OpenAI). Implementada na Task 9; até lá não agenda nada.
  class AutoReplyJob < ApplicationJob
    queue_as :whatsapp
    def self.schedule(conversation, message) = nil
  end
end
