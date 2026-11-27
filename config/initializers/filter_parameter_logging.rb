# Be sure to restart your server when you modify this file.

# Configure parameters to be filtered from the log file. Use this to limit dissemination of
# sensitive information. See the ActiveSupport::ParameterFilter documentation for supported
# notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :secret, :token, :_key, :crypt, :salt, :certificate, :otp, :ssn
]

# Mensagens, mídia e webhooks com dados dos clientes não podem ir para o log
# (mesma lista do Honey).
Rails.application.config.filter_parameters += [:apikey, :qr_data, :base64, :media, :data, :body, :webhook, :authorization]
