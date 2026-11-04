module Whatsapp
  # Escolhe o número responsável por enviar uma mensagem da automação.
  module Router
    def self.pick(campaign:, phone:, prefer: nil, strict: false)
      return unless campaign

      campaign.with_lock do
        links = campaign.whatsapp_campaign_connections.includes(:connection).to_a
                     .select { |l| l.connection.client_id == campaign.client_id && l.connection.connected? }
        next if links.empty?

        if strict # só o número preferido, nunca outro
          chosen = prefer && links.find { |l| l.connection_id == prefer.id }
          next unless chosen

          chosen.update!(last_assigned_at: Time.current)
          next chosen.connection
        end

        chosen = links.find { |l| prefer && l.connection_id == prefer.id } || sticky(links, phone) || oldest(links)
        chosen.update!(last_assigned_at: Time.current)
        chosen.connection
      end
    end

    def self.sticky(links, phone)
      normalized = Phone.normalize(phone)
      return unless normalized

      ids = Contact.where(connection_id: links.map(&:connection_id), phone: normalized).pluck(:connection_id)
      links.find { |l| ids.include?(l.connection_id) }
    end

    def self.oldest(links)
      links.min_by { |l| [l.last_assigned_at ? 1 : 0, l.last_assigned_at || Time.at(0), l.id] }
    end
    private_class_method :sticky, :oldest
  end
end
