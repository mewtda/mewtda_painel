module Webhooks
  # Webhook da API Oficial do WhatsApp (app Mewtda na Meta). GET: verificação da assinatura do webhook;
  # POST: eventos assinados com o segredo do app (X-Hub-Signature-256). Hoje só usa os status das mensagens.
  class WhatsappCloudController < ActionController::API
    MAX_BYTES = 512.kilobytes

    def verify
      token = ENV['WHATSAPP_WEBHOOK_VERIFY_TOKEN'].to_s
      valid = params['hub.mode'] == 'subscribe' && token.present? &&
              ActiveSupport::SecurityUtils.secure_compare(params['hub.verify_token'].to_s, token)
      return head :forbidden unless valid

      render plain: params['hub.challenge'].to_s
    end

    def create
      raw = request.body.read(MAX_BYTES + 1).to_s
      return head :payload_too_large if raw.bytesize > MAX_BYTES
      return head :forbidden unless signed?(raw)

      Whatsapp::Cloud::StatusWebhook.process(JSON.parse(raw))
      head :ok
    rescue JSON::ParserError
      head :bad_request
    end

    private

    def signed?(raw)
      secret = ENV['META_APP_SECRET'].to_s
      return false if secret.blank?

      expected = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', secret, raw)}"
      ActiveSupport::SecurityUtils.secure_compare(request.headers['X-Hub-Signature-256'].to_s, expected)
    end
  end
end
