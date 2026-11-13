class Campaign < ApplicationRecord
  STATUSES = {
    'draft' => 'Rascunho', 'scheduled' => 'Agendada', 'sending' => 'Enviando',
    'paused' => 'Pausada', 'sent' => 'Enviada', 'cancelled' => 'Cancelada'
  }.freeze
  SEND_MODES = %w[now scheduled window].freeze
  CHANNELS = { 'email' => 'E-mail' }.freeze
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
  RESUME_HOUR = 8
  RUNNABLE = %w[scheduled sending paused].freeze

  belongs_to :client
  belongs_to :email_template, optional: true
  belongs_to :segment, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :published_by, class_name: 'User', optional: true
  has_many :recipients, class_name: 'CampaignRecipient', dependent: :delete_all

  attr_writer :scheduled_on, :scheduled_time

  before_validation :compose_scheduled_at

  validates :name, length: { maximum: 120 }
  validates :status, inclusion: { in: STATUSES.keys }
  validates :send_mode, inclusion: { in: SEND_MODES }
  validates :channel, inclusion: { in: CHANNELS.keys }
  validates :window_from, :window_to, format: { with: TIME_FORMAT }
  validate :template_and_segment_belong_to_client

  def window_days=(value)
    super(Array(value).compact_blank.map(&:to_i).select { |day| (0..6).cover?(day) }.uniq.sort)
  end

  def draft? = status == 'draft'
  def cancelable? = status.in?(RUNNABLE)

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

  def status_note(now = Time.current)
    return unless status.in?(RUNNABLE)
    return 'Confira o e-mail e o público desta campanha' if next_run_at.nil?

    when_label = I18n.l(next_run_at, format: '%d/%m às %H:%M')
    return "Começa em #{when_label}" if status == 'scheduled' && next_run_at > now
    return "Continua em #{when_label}" if next_run_at > now

    'Enviando agora'
  end
  def status_label = STATUSES.fetch(status)
  def channel_label = CHANNELS.fetch(channel)
  def display_name = name.presence || 'Campanha sem nome'

  def scheduled_on = @scheduled_on || scheduled_at&.to_date
  def scheduled_time = @scheduled_time || scheduled_at&.strftime('%H:%M')

  def window = Campaigns::SendWindow.new(days: window_days, from: window_from, to: window_to)

  def audience = Campaigns::Audience.new(client, segment).call

  # Primeiro instante em que a campanha pode sair: agora, a data marcada ou a
  # próxima abertura da janela de envio.
  def first_send_at(from = Time.current)
    case send_mode
    when 'scheduled' then [scheduled_at, from].compact.max
    when 'window' then window.next_opening(from) || from
    else from
    end
  end

  # Depois de bater o limite diário a campanha continua às 8h do dia seguinte,
  # ou na próxima abertura da janela de envio.
  def resume_at(from = Time.current)
    start = first_send_at(from).in_time_zone.tomorrow.beginning_of_day
    return window.next_opening(start) if send_mode == 'window' && window.valid?

    start.change(hour: RESUME_HOUR)
  end

  # Textos do aviso de limite diário: sempre com o dia da semana e a data.
  def first_day_label(from = Time.current)
    time = first_send_at(from)
    label = day_label(time, from)
    case send_mode
    when 'scheduled' then scheduled_at && scheduled_at > from ? "#{label} às #{time.strftime('%H:%M')}" : label
    when 'window' then "#{label}, das #{window_from} às #{window_to}"
    else label
    end
  end

  def resume_label(from = Time.current)
    time = resume_at(from)
    label = day_label(time, from)
    send_mode == 'window' ? "#{label}, das #{window_from} às #{window_to}" : "#{label} às #{time.strftime('%H:%M')}"
  end

  def timing_summary
    case send_mode
    when 'scheduled' then scheduled_at ? I18n.l(scheduled_at, format: '%d/%m/%Y às %H:%M') : 'Escolha a data e a hora'
    when 'window' then window.summary
    else 'Assim que você confirmar'
    end
  end

  def missing_steps
    steps = []
    steps << 'Dê um nome à campanha' if name.blank?
    steps << 'Escolha o e-mail' unless email_template
    steps << 'Escolha para quem enviar' unless segment
    steps << 'Escolha a data e a hora' if send_mode == 'scheduled' && !scheduled_at
    steps << 'Escolha os dias e o horário' if send_mode == 'window' && !window.valid?
    steps
  end

  def step_done
    {
      'name' => name.present?, 'template' => email_template.present?, 'audience' => segment.present?,
      'timing' => send_mode == 'now' || (send_mode == 'scheduled' && scheduled_at.present?) ||
                  (send_mode == 'window' && window.valid?)
    }
  end

  private

  def day_label(time, from)
    label = I18n.l(time, format: '%A, %d/%m').upcase_first
    time.to_date == from.in_time_zone.to_date ? "#{label} (hoje)" : label
  end

  def compose_scheduled_at
    return if @scheduled_on.nil? && @scheduled_time.nil?

    date = (@scheduled_on.presence || scheduled_on).to_s
    time = (@scheduled_time.presence || scheduled_time).to_s
    self.scheduled_at = (Time.zone.parse("#{date} #{time}") if date.present? && time.present?)
  rescue ArgumentError
    self.scheduled_at = nil
  end

  def template_and_segment_belong_to_client
    errors.add(:email_template_id, 'não pertence a esta loja') if email_template && email_template.client_id != client_id
    errors.add(:segment_id, 'não pertence a esta loja') if segment && segment.client_id != client_id
  end
end
