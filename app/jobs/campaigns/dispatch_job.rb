module Campaigns
  # Envia uma mensagem da campanha (e-mail ou WhatsApp) em lotes. No primeiro disparo grava a lista de
  # pessoas daquele canal (a "foto" do público); depois envia um lote por execução e para quando bate o
  # limite diário, a Meta/AWS pede para esperar, falta configuração ou a loja cancela a campanha.
  # O próximo horário fica em next_run_at da mensagem, que também serve de reserva contra duas execuções
  # ao mesmo tempo. Ao final, a campanha recalcula status e contagens a partir das mensagens.
  # Mensagem contínua (continuous_until): a cada rodada inclui quem entrou no segmento e, enquanto o prazo
  # não termina, volta a olhar de tempos em tempos em vez de encerrar.
  class DispatchJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 150
    LEASE = 5.minutes
    THROTTLE = 0.07
    BACKOFF = 1.minute
    CHECK_EVERY = 10
    SENDERS = { 'email' => Senders::Email, 'whatsapp' => Senders::Whatsapp }.freeze

    attr_reader :message

    def perform(message_id)
      @message = claim(message_id)
      return unless @message

      run
      campaign.refresh_from_messages!
    end

    private

    def batch_size = BATCH_SIZE

    def throttle = THROTTLE

    def campaign = message.campaign

    def client = campaign.client

    def sender = @sender ||= SENDERS.fetch(message.channel).new(message)

    def run
      return cancel_message unless campaign.channel_enabled?(message.channel)

      note, retry_at = sender.blocker
      return message.update!(status: 'paused', next_run_at: retry_at, note:) if note

      message.update_columns(note: nil) if message.note
      if !message.audience_frozen_at then freeze_audience
      elsif message.continuous? then add_newcomers
      end
      send_batch
      finish_run
    end

    def claim(message_id)
      now = Time.current
      claimed = CampaignMessage.where(id: message_id, status: CampaignMessage::RUNNABLE).where(next_run_at: ..now)
                               .update_all(status: 'sending', next_run_at: now + LEASE, updated_at: now)
      @leased_at = now
      CampaignMessage.find(message_id) if claimed == 1
    end

    def cancel_message
      message.update!(status: 'cancelled', next_run_at: nil)
    end

    def freeze_audience
      now = Time.current
      CampaignMessage.transaction do
        audience = Audience.new(client, campaign.segments.to_a, channel: message.channel)
        rows = []
        audience.each_recipient do |profile, address|
          rows << recipient_row(profile, address, now)
          flush(rows) if rows.size >= 1000
        end
        flush(rows)
        message.update!(audience_frozen_at: now, started_at: now, status: 'sending', note: nil,
                        recipients_count: message.recipients.count)
      end
    end

    # Mensagem contínua: inclui quem entrou no segmento desde a última rodada. Quem já está na lista desta
    # mensagem (enviado, falha ou pendente) é ignorado pelo índice único — ninguém recebe a mesma mensagem duas vezes.
    def add_newcomers
      now = Time.current
      rows = []
      Audience.new(client, campaign.segments.to_a, channel: message.channel).each_recipient do |profile, address|
        rows << recipient_row(profile, address, now)
        flush(rows) if rows.size >= 1000
      end
      flush(rows)
      message.update_columns(recipients_count: message.recipients.count, updated_at: now)
    end

    def recipient_row(profile, address, now)
      row = { campaign_id: campaign.id, campaign_message_id: message.id, channel: message.channel,
              customer_id: profile.customer_id, name: profile.name, status: 'pending', created_at: now, updated_at: now }
      message.whatsapp? ? row.merge(phone: address, email: nil) : row.merge(email: address)
    end

    def flush(rows)
      return if rows.empty?

      index = message.whatsapp? ? 'index_campaign_recipients_unique_phone' : 'index_campaign_recipients_unique_email'
      CampaignRecipient.insert_all(rows, unique_by: index)
      rows.clear
    end

    def send_batch
      catch(:stop) do
        message.recipients.where(status: 'pending').order(:id).limit(batch_size).each_with_index do |recipient, index|
          stop_for(nil, :cancelled) if (index % CHECK_EVERY).zero? && !still_running?
          renew_lease
          check_limit
          result = sender.deliver(recipient)
          stop_for(result[1], result[0], result[2]) if result.is_a?(Array)
          sleep(throttle)
        end
      end
    end

    def check_limit
      stop_for(message.resume_at, :pause) if Billing::Usage.new(client).limit_reached?(message.channel)
    end

    # Renova a reserva enquanto o lote ainda está enviando (a Meta pode demorar até 15 s por chamada),
    # para o TickJob não entregar a mesma mensagem a outro job no meio do caminho.
    def renew_lease
      now = Time.current
      return if now - @leased_at < LEASE / 5

      renewed = CampaignMessage.where(id: message.id, status: 'sending').update_all(next_run_at: now + LEASE)
      stop_for(nil, :cancelled) if renewed.zero?
      @leased_at = now
    end

    def still_running?
      CampaignMessage.where(id: message.id, status: CampaignMessage::RUNNABLE).exists?
    end

    def stop_for(next_run, reason, note = nil)
      @next_run = next_run
      @reason = reason
      @note = note
      throw :stop
    end

    def finish_run
      message.reload
      message.recount!
      return if message.status == 'cancelled'
      return wait_for_newcomers if !pending? && message.continuing?
      return message.update!(status: 'sent', finished_at: Time.current, next_run_at: nil) unless pending?

      case @reason
      when :pause, :wait then message.update!(status: 'paused', next_run_at: @next_run, note: @note)
      else continue_now
      end
    end

    def pending? = message.recipients.where(status: 'pending').exists?

    # Todos da lista já receberam, mas a mensagem ainda aceita novos: volta a olhar o segmento daqui a pouco
    # (a última rodada acontece logo depois do prazo, para pegar quem entrou no finalzinho).
    def wait_for_newcomers
      next_check = [Time.current + CampaignMessage::CONTINUOUS_EVERY, message.continuous_until].min
      message.update!(status: 'scheduled', next_run_at: next_check)
    end

    def continue_now
      message.update!(status: 'sending', next_run_at: Time.current)
      self.class.perform_later(message.id)
    end
  end
end
