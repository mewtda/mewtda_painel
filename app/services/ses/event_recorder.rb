module Ses
  class EventRecorder
    TYPES = { 'Delivery' => 'delivery', 'Bounce' => 'bounce', 'Complaint' => 'complaint', 'Open' => 'open',
              'Click' => 'click', 'Reject' => 'reject' }.freeze
    SUPPRESSIONS = { 'bounce' => 'bounce', 'complaint' => 'complaint' }.freeze

    def initialize(payload)
      @payload = payload
    end

    def call
      return unless event_type && client && target

      event = EmailEvent.create!(attributes)
      suppress(event)
      event
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    private

    attr_reader :payload

    def event_type = TYPES[payload['eventType'] || payload['notificationType']]
    def mail = payload['mail'].to_h
    def event_tag(name) = mail.dig('tags', name)&.first
    def client = @client ||= Client.find_by(id: event_tag('client_id'))

    def target
      @target ||= case event_tag('source')
                  when 'campaign' then campaign_target
                  when 'back_in_stock' then alert_target
                  end
    end

    def campaign_target
      campaign = client.campaigns.find_by(id: event_tag('campaign_id'))
      return unless campaign

      { source: 'campaign', campaign:, campaign_recipient: campaign.recipients.find_by(id: event_tag('recipient_id')) }
    end

    def alert_target
      alert = client.back_in_stock_alerts.find_by(id: event_tag('alert_id'))
      { source: 'back_in_stock', back_in_stock_alert: alert } if alert
    end

    def attributes
      target.merge(client:, event_type:, ses_message_id: mail['messageId'], occurred_at: occurred_at,
                   bounce_type: payload.dig('bounce', 'bounceType')&.downcase, link: payload.dig('click', 'link'))
    end

    def occurred_at
      Time.zone.parse(payload.dig(event_type, 'timestamp').to_s) || Time.zone.parse(mail['timestamp'].to_s) || Time.current
    end

    def suppress(event)
      return unless SUPPRESSIONS.key?(event.event_type)
      return if event.event_type == 'bounce' && event.bounce_type != 'permanent'

      address = recipient_address
      EmailSuppression.unsubscribe!(client, address, source: SUPPRESSIONS.fetch(event.event_type)) if address.present?
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def recipient_address
      listed = payload.dig('bounce', 'bouncedRecipients') || payload.dig('complaint', 'complainedRecipients')
      listed&.first&.dig('emailAddress') || mail['destination']&.first
    end
  end
end
