module Campaigns
  # Envia uma campanha em lotes. No primeiro disparo grava a lista de pessoas
  # (a "foto" do público); depois envia um lote por execução e para quando bate
  # o limite diário, fecha a janela de envio ou a loja cancela a campanha.
  # O próximo horário fica em next_run_at, que também serve de reserva contra
  # duas execuções ao mesmo tempo.
  class DispatchJob < ApplicationJob
    queue_as :default

    BATCH_SIZE = 150
    LEASE = 5.minutes
    THROTTLE = 0.07
    BACKOFF = 1.minute
    CHECK_EVERY = 10

    attr_reader :campaign

    def perform(campaign_id)
      @campaign = claim(campaign_id)
      return unless @campaign
      return pause_without_date unless sendable?

      freeze_audience unless campaign.audience_frozen_at
      send_batch
      finish_run
    end

    private

    def batch_size = BATCH_SIZE

    def throttle = THROTTLE

    def client = campaign.client

    def claim(campaign_id)
      now = Time.current
      claimed = Campaign.where(id: campaign_id, status: Campaign::RUNNABLE).where(next_run_at: ..now)
                        .update_all(status: 'sending', next_run_at: now + LEASE, updated_at: now)
      Campaign.find(campaign_id) if claimed == 1
    end

    def sendable?
      campaign.email_template && (campaign.audience_frozen_at || campaign.segment)
    end

    def pause_without_date
      campaign.update!(status: 'paused', next_run_at: nil)
    end

    def freeze_audience
      now = Time.current
      Campaign.transaction do
        Audience.new(client, campaign.segment).recipients_scope.find_in_batches(batch_size: 1000) do |profiles|
          rows = profiles.map do |profile|
            { campaign_id: campaign.id, customer_id: profile.customer_id, email: profile.email.downcase,
              name: profile.name, status: 'pending', created_at: now, updated_at: now }
          end
          CampaignRecipient.insert_all(rows, unique_by: %i[campaign_id email])
        end
        campaign.update!(audience_frozen_at: now, started_at: now, status: 'sending',
                         recipients_count: campaign.recipients.count)
      end
    end

    def send_batch
      catch(:stop) do
        campaign.recipients.where(status: 'pending').order(:id).limit(batch_size).each_with_index do |recipient, index|
          check_before_sending(index)
          deliver(recipient)
          sleep(throttle)
        end
      end
    end

    def check_before_sending(index)
      stop_for(nil, :cancelled) if (index % CHECK_EVERY).zero? && !still_running?
      stop_for(campaign.window.next_opening, :wait) if campaign.send_mode == 'window' && !campaign.window.open?
      stop_for(Time.current + 1.hour, :pause) unless client.ses_domain_verified?
      stop_for(campaign.resume_at, :pause) if Billing::Usage.new(client).limit_reached?('email')
    end

    def still_running?
      Campaign.where(id: campaign.id, status: Campaign::RUNNABLE).exists?
    end

    def stop_for(next_run, reason)
      @next_run = next_run
      @reason = reason
      throw :stop
    end

    def deliver(recipient)
      return recipient.update!(status: 'blocked') if EmailSuppression.suppressed?(client, recipient.email)

      message = message_for(recipient)
      sent = Ses::SendEmailService.new(client).call(
        to: recipient.email, subject: message.subject, html_body: message.html, text_body: message.text,
        unsubscribe_url: message.unsubscribe_url,
        tags: { source: 'campaign', campaign_id: campaign.id, recipient_id: recipient.id }
      )
      return recipient.update!(status: 'sent', sent_at: Time.current) if sent

      stop_for(campaign.resume_at, :pause) if Billing::Usage.new(client).limit_reached?('email')
      recipient.update!(status: 'failed', error: 'O envio não foi aceito')
    rescue Aws::SESV2::Errors::TooManyRequestsException
      stop_for(Time.current + BACKOFF, :wait)
    rescue Aws::Errors::ServiceError => e
      recipient.update!(status: 'failed', error: e.message.to_s.first(250))
    end

    def message_for(recipient)
      EmailTemplates::Message.new(
        campaign.email_template,
        variables: { nome: recipient.name.to_s.split.first.presence || 'cliente', loja: client.name },
        default_url: default_url, logo_url: logo_url,
        unsubscribe_url: EmailSuppression.unsubscribe_url(client, recipient.email, template: campaign.email_template)
      )
    end

    def default_url
      @default_url ||= client.storefront_url.then { |url| url.match?(%r{\Ahttps?://[^/]+\z}) ? url : BackInStockSetting::WIDGET_HOST }
    end

    def logo_url
      return unless client.logo.attached?

      Rails.application.routes.url_helpers.rails_blob_url(client.logo, host: BackInStockSetting::WIDGET_HOST)
    end

    def finish_run
      campaign.reload
      campaign.recount!
      return if campaign.status == 'cancelled'
      return finish_campaign unless campaign.recipients.where(status: 'pending').exists?

      case @reason
      when :pause, :wait then campaign.update!(status: 'paused', next_run_at: @next_run)
      else continue_now
      end
    end

    def finish_campaign
      campaign.update!(status: 'sent', finished_at: Time.current, next_run_at: nil)
    end

    def continue_now
      campaign.update!(status: 'sending', next_run_at: Time.current)
      self.class.perform_later(campaign.id)
    end
  end
end
