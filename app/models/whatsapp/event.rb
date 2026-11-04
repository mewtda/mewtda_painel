module Whatsapp
  class Event < ApplicationRecord
    belongs_to :connection
    encrypts :payload
    KINDS = %w[qrcode.updated connection.update messages.upsert messages.set send.message messages.update].freeze

    def self.capture!(connection, kind, data, occurred_at: Time.current)
      return unless KINDS.include?(kind)

      # QR/connection events carry a timestamp; message dedup is also enforced by provider ID.
      raw = { data: data, at: occurred_at.iso8601(6) }.to_json
      event = create_or_find_by!(connection: connection, digest: Digest::SHA256.hexdigest(kind + raw)) do |e|
        e.kind = kind
        e.payload = data.to_json
        e.occurred_at = occurred_at
      end
      Whatsapp::EventJob.perform_later(event.id) unless event.processed_at
      event
    end
  end
end
