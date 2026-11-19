# Uma mensagem da campanha: um canal (e-mail ou WhatsApp), um modelo e quando sai.
# Cada mensagem tem seu próprio ciclo de envio (público congelado, reserva, contagens).
class CampaignMessage < ApplicationRecord
  STATUSES = %w[draft scheduled sending paused sent cancelled].freeze
  RUNNABLE = %w[scheduled sending paused].freeze
  FINISHED = %w[sent cancelled].freeze
  CHANNELS = %w[email whatsapp].freeze
  CHANNEL_LABELS = { 'email' => 'E-mail', 'whatsapp' => 'WhatsApp' }.freeze
  RESUME_HOUR = 8

  belongs_to :campaign, inverse_of: :messages
  belongs_to :email_template, optional: true
  belongs_to :whatsapp_template, optional: true
  has_many :recipients, class_name: 'CampaignRecipient', inverse_of: :message, dependent: :delete_all

  attr_accessor :send_now
  attr_writer :send_on, :send_time

  before_validation :compose_send_at

  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validate :templates_belong_to_store

  def email? = channel == 'email'
  def whatsapp? = channel == 'whatsapp'
  def runnable? = status.in?(RUNNABLE)
  def finished? = status.in?(FINISHED)
  def channel_label = CHANNEL_LABELS.fetch(channel, channel)
  def template = whatsapp? ? whatsapp_template : email_template

  def template_name
    whatsapp? ? whatsapp_template&.label : email_template&.name
  end

  def send_on = @send_on || send_at&.to_date&.iso8601
  def send_time = @send_time || send_at&.strftime('%H:%M')

  def when_label
    send_at ? I18n.l(send_at, format: '%d/%m/%Y às %H:%M') : 'Assim que você confirmar'
  end

  def first_send_at(from = Time.current) = [send_at, from].compact.max

  # Depois de bater o limite diário a mensagem continua às 8h do dia seguinte.
  def resume_at(from = Time.current)
    from.in_time_zone.tomorrow.beginning_of_day.change(hour: RESUME_HOUR)
  end

  def recount!
    counts = recipients.group(:status).count
    update_columns(sent_count: counts.fetch('sent', 0), failed_count: counts.fetch('failed', 0),
                   blocked_count: counts.fetch('blocked', 0))
  end

  def progress_label
    return unless recipients_count

    parts = ["#{sent_count} de #{recipients_count} enviados"]
    parts << "#{failed_count} #{'falha'.pluralize(failed_count)}" if failed_count.positive?
    parts << "#{blocked_count} #{'bloqueio'.pluralize(blocked_count)}" if blocked_count.positive?
    parts.join(' · ')
  end

  def sent_cost
    email? ? sent_count.to_i * Billing::Invoice::EMAIL_PRICE_PER_THOUSAND / 1000 : 0
  end

  private

  def compose_send_at
    if send_now.to_s == '1'
      self.send_at = nil
      return
    end
    return if @send_on.nil? && @send_time.nil?

    date = (@send_on.presence || send_on).to_s
    time = (@send_time.presence || send_time).to_s
    self.send_at = (Time.zone.parse("#{date} #{time}") if date.present? && time.present?)
  rescue ArgumentError
    self.send_at = nil
  end

  def templates_belong_to_store
    client_id = campaign&.client_id
    if email_template && email_template.client_id != client_id
      errors.add(:email_template_id, 'não pertence a esta loja')
    end
    return unless whatsapp_template && whatsapp_template.client_id != client_id

    errors.add(:whatsapp_template_id, 'não pertence a esta loja')
  end
end
