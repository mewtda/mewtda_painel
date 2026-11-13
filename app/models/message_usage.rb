class MessageUsage < ApplicationRecord
  CHANNELS = %w[email].freeze

  belongs_to :client

  validates :channel, inclusion: { in: CHANNELS }

  # Soma atômica no contador do dia (uma linha por cliente/canal/dia).
  def self.track!(client, channel, amount = 1, day: Time.zone.today)
    raise ArgumentError, "canal desconhecido: #{channel}" unless CHANNELS.include?(channel)

    now = Time.current
    upsert_all(
      [{ client_id: client.id, channel:, day:, count: amount, created_at: now, updated_at: now }],
      unique_by: %i[client_id channel day],
      on_duplicate: Arel.sql('count = message_usages.count + EXCLUDED.count, updated_at = EXCLUDED.updated_at'),
      record_timestamps: false
    )
  end
end
