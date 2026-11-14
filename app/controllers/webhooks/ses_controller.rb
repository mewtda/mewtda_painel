module Webhooks
  class SesController < ActionController::API
    MAX_BYTES = 256.kilobytes

    def create
      raw = request.body.read(MAX_BYTES + 1).to_s
      return head :payload_too_large if raw.bytesize > MAX_BYTES

      message = Ses::SnsMessage.new(raw)
      return head :forbidden unless message.valid?

      message.confirm! if message.confirmation?
      Ses::ProcessEventJob.perform_later(message.message) if message.notification?
      head :ok
    end
  end
end
