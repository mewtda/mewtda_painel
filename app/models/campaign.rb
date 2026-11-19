# Campanha: nome, segmentos, canais ligados e uma ou mais mensagens (e-mail e/ou WhatsApp), cada uma
# com sua data. Status, contagens e próximo envio são agregados a partir das mensagens.
# Os campos antigos (email_template_id, segment_id, send_mode, scheduled_at, janela) não são mais usados.
class Campaign < ApplicationRecord
  STATUSES = {
    'draft' => 'Rascunho', 'scheduled' => 'Agendada', 'sending' => 'Enviando',
    'paused' => 'Pausada', 'sent' => 'Enviada', 'cancelled' => 'Cancelada'
  }.freeze
  CHANNELS = CampaignMessage::CHANNEL_LABELS
  RUNNABLE = CampaignMessage::RUNNABLE

  belongs_to :client
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :published_by, class_name: 'User', optional: true
  # Destinatários antes das mensagens: apagam primeiro.
  has_many :recipients, class_name: 'CampaignRecipient', dependent: :delete_all
  has_many :messages, -> { order(Arel.sql('campaign_messages.send_at ASC NULLS FIRST, campaign_messages.position, campaign_messages.id')) },
           class_name: 'CampaignMessage', dependent: :destroy, inverse_of: :campaign
  has_many :campaign_segments, dependent: :delete_all
  has_many :segments, through: :campaign_segments

  accepts_nested_attributes_for :messages, allow_destroy: true

  validates :name, length: { maximum: 120 }
  validates :status, inclusion: { in: STATUSES.keys }
  validate :segments_belong_to_client

  def draft? = status == 'draft'
  def cancelable? = status.in?(RUNNABLE)
  def status_label = STATUSES.fetch(status)
  def display_name = name.presence || 'Campanha sem nome'

  def channel_enabled?(channel)
    channel.to_s == 'whatsapp' ? whatsapp_enabled : email_enabled
  end

  def enabled_channels = CampaignMessage::CHANNELS.select { |channel| channel_enabled?(channel) }

  def live_messages = messages.reject(&:marked_for_destruction?)

  def active_messages
    live_messages.select { |message| channel_enabled?(message.channel) && message.status != 'cancelled' }
  end

  def messages_for(channel) = live_messages.select { |message| message.channel == channel.to_s }

  def whatsapp_ready? = Whatsapp::Cloud::Api.new(client).configured?

  def missing_steps(now = Time.current)
    steps = []
    steps << 'Dê um nome à campanha' if name.blank?
    steps << 'Escolha para quem enviar' if segments.empty?
    steps << 'Ative o e-mail ou o WhatsApp' if enabled_channels.empty?
    steps << 'Configure a API Oficial do WhatsApp da loja' if whatsapp_enabled && !whatsapp_ready?
    enabled_channels.each do |channel|
      list = messages_for(channel)
      steps << "Adicione uma mensagem de #{channel == 'email' ? 'e-mail' : 'WhatsApp'}" if list.empty?
      list.each_with_index { |message, index| steps.concat(message_steps(message, index + 1, now)) }
    end
    steps
  end

  def timing_summary
    list = active_messages
    return 'Adicione as mensagens' if list.empty?

    dates = list.map(&:send_at)
    return list.one? ? 'Assim que você confirmar' : "#{list.size} mensagens · assim que você confirmar" if dates.all?(&:nil?)
    return I18n.l(dates.first, format: '%d/%m/%Y às %H:%M') if list.one?

    first = dates.include?(nil) ? 'ao confirmar' : I18n.l(dates.compact.min, format: '%d/%m %H:%M')
    "#{list.size} mensagens · #{first} a #{I18n.l(dates.compact.max, format: '%d/%m %H:%M')}"
  end

  # Recalcula status, contagens e próximo envio a partir das mensagens já confirmadas.
  # Sob trava da linha da campanha: duas mensagens terminando juntas não sobrescrevem uma à outra.
  # Uma campanha cancelada pela loja continua cancelada.
  def refresh_from_messages!
    with_lock do
      list = messages.reload.reject { |message| message.status == 'draft' }
      next if list.empty?

      runnable = list.select(&:runnable?)
      counted = list.select(&:recipients_count)
      update_columns(
        status: status == 'cancelled' ? 'cancelled' : aggregate_status(list.map(&:status)),
        recipients_count: counted.any? ? counted.sum(&:recipients_count) : nil,
        sent_count: list.sum(&:sent_count), failed_count: list.sum(&:failed_count), blocked_count: list.sum(&:blocked_count),
        started_at: list.filter_map(&:started_at).min,
        next_run_at: runnable.filter_map(&:next_run_at).min,
        finished_at: runnable.empty? ? list.filter_map(&:finished_at).max : nil,
        audience_frozen_at: list.filter_map(&:audience_frozen_at).min,
        updated_at: Time.current
      )
    end
  end

  def cancel!
    transaction do
      messages.where(status: RUNNABLE + ['draft']).update_all(status: 'cancelled', next_run_at: nil, updated_at: Time.current)
      update!(status: 'cancelled', next_run_at: nil)
    end
  end

  def sent_cost = messages.select(&:email?).sum(&:sent_cost)

  def progress_label
    return unless recipients_count

    parts = ["#{sent_count} de #{recipients_count} enviados"]
    parts << "#{failed_count} #{'falha'.pluralize(failed_count)}" if failed_count.positive?
    parts << "#{blocked_count} #{'bloqueio'.pluralize(blocked_count)}" if blocked_count.positive?
    parts.join(' · ')
  end

  def status_note(now = Time.current)
    return unless status.in?(RUNNABLE)
    return 'Enviando agora' if status == 'sending'

    note = messages.find { |message| message.status == 'paused' && message.note.present? }&.note if status == 'paused'
    return note if note
    return if next_run_at.nil?
    return 'Enviando agora' if next_run_at <= now

    when_label = I18n.l(next_run_at, format: '%d/%m às %H:%M')
    status == 'paused' ? "Continua em #{when_label}" : "Próxima mensagem em #{when_label}"
  end

  private

  def aggregate_status(statuses)
    return 'sending' if statuses.include?('sending')
    return(statuses.include?('sent') ? 'sent' : 'cancelled') if statuses.all? { |s| s.in?(CampaignMessage::FINISHED) }
    return 'paused' if statuses.include?('paused')

    'scheduled'
  end

  def message_steps(message, number, now)
    label = "#{message.channel == 'email' ? 'e-mail' : 'WhatsApp'} #{number}"
    template = message.template
    return ["Escolha o modelo da mensagem de #{label}"] unless template
    return [] if message.status != 'draft'

    steps = []
    if message.whatsapp? && !template.approved?
      steps << "O modelo \"#{template.label}\" (WhatsApp #{number}) ainda não foi aprovado pela Meta"
    end
    steps << "A data da mensagem de #{label} já passou" if message.send_at && message.send_at <= now
    steps << "Escolha a data e a hora da mensagem de #{label}" if message.send_now.to_s == '0' && message.send_at.nil?
    steps
  end

  def segments_belong_to_client
    return if segments.all? { |segment| segment.client_id == client_id }

    errors.add(:segment_ids, 'não pertencem a esta loja')
  end
end
