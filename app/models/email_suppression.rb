# Lista de recusa: e-mails que pediram pra não receber mais nada da loja.
# Ses::SendEmailService consulta essa lista antes de qualquer envio.
class EmailSuppression < ApplicationRecord
  SOURCES = {
    'unsubscribe_link' => 'Link "Não quero mais receber"',
    'manual' => 'Adicionado manualmente'
  }.freeze

  TOKEN_PURPOSE = :email_unsubscribe

  belongs_to :client

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }

  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 },
                    uniqueness: { scope: :client_id, message: 'já está na lista de recusa' }
  validates :source, inclusion: { in: SOURCES.keys }

  scope :search, lambda { |term|
    next if term.blank?

    where('email ILIKE ?', "%#{sanitize_sql_like(term.strip)}%")
  }

  def self.suppressed?(client, email)
    return false if email.blank?

    where(client:, email: normalize_value_for(:email, email)).exists?
  end

  # Registra a recusa (idempotente) e cancela os avisos de estoque pendentes
  # desse e-mail, pra que nada mais seja disparado pra ele.
  def self.unsubscribe!(client, email, source: 'unsubscribe_link')
    normalized = normalize_value_for(:email, email)
    suppression = find_by(client:, email: normalized) || create!(client:, email: normalized, source:)
    client.back_in_stock_alerts.pending.where(email: suppression.email).find_each(&:unsubscribe!)
    suppression
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.unsubscribe_token(client, email)
    verifier.generate({ 'client_id' => client.id, 'email' => normalize_value_for(:email, email) })
  end

  def self.unsubscribe_url(client, email)
    path = Rails.application.routes.url_helpers.widget_email_unsubscribe_path(token: unsubscribe_token(client, email))
    "#{BackInStockSetting::WIDGET_HOST}#{path}"
  end

  # Devolve [client, email] de um token válido, ou nil.
  def self.resolve_token(token)
    data = verifier.verified(token.to_s)
    return unless data.is_a?(Hash)

    client = Client.find_by(id: data['client_id'])
    [client, data['email']] if client && data['email'].present?
  end

  def self.verifier
    @verifier ||= ActiveSupport::MessageVerifier.new(
      Rails.application.key_generator.generate_key(TOKEN_PURPOSE.to_s), url_safe: true, serializer: JSON
    )
  end

  def source_label
    SOURCES.fetch(source, source)
  end
end
