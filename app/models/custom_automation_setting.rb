# Configuração de uma rotina personalizada (CustomAutomations::Registry::ROUTINES) para um cliente: quem recebe,
# limites etc. ficam em `settings` (jsonb), e `last_run_at` evita repetir um envio que já saiu.
class CustomAutomationSetting < ApplicationRecord
  EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

  belongs_to :client

  validates :kind, presence: true, uniqueness: { scope: :client_id }
  validate :recipients_are_emails

  def self.for(client, kind)
    find_or_initialize_by(client:, kind: kind.to_s)
  end

  def recipients = Array(settings['recipients'])

  # Aceita uma lista separada por linha, vírgula ou ponto e vírgula.
  def recipients_text=(text)
    self.settings = settings.merge('recipients' => text.to_s.split(/[\s,;]+/).map { |e| e.strip.downcase }
                                                       .compact_blank.uniq)
  end

  def recipients_text = recipients.join("\n")

  def low_stock_limit
    value = settings['low_stock_limit'].to_i
    value.positive? ? value : 3
  end

  def low_stock_limit=(value)
    self.settings = settings.merge('low_stock_limit' => value.to_i)
  end

  def enabled? = settings.fetch('enabled', true)

  def enabled=(value)
    self.settings = settings.merge('enabled' => ActiveModel::Type::Boolean.new.cast(value))
  end

  private

  def recipients_are_emails
    invalid = recipients.grep_v(EMAIL)
    errors.add(:base, "E-mail inválido: #{invalid.join(', ')}") if invalid.any?
  end
end
