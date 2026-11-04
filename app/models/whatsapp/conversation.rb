module Whatsapp
  class Conversation < ApplicationRecord
    belongs_to :connection
    belongs_to :contact
    has_many :messages, dependent: :restrict_with_exception
    has_many :reads, dependent: :delete_all
    validates :state, inclusion: { in: %w[open closed] }
    validate { errors.add(:contact, 'de outro número') if contact && contact.connection_id != connection_id }

    def self.visible_to(user, client:)
      where(connection_id: Connection.visible_to(user, client: client).select(:id))
    end

    def unread_count(user)
      cursor = reads.find_by(user_id: user.id)&.last_message_id || 0
      messages.where(direction: 'incoming', historical: false).where('id > ?', cursor).count
    end

    # O cliente escreveu: conversa encerrada volta a ficar aberta.
    def customer_wrote!
      self.state = 'open' if state == 'closed'
      save! if changed?
    end

    # Alguém da equipe respondeu (pelo painel ou pelo celular): a resposta automática pausa.
    def team_replied!
      assign_attributes(state: 'open', auto_reply_paused: true)
      save! if changed?
    end

    def mark_read!(user, message_id)
      with_lock do
        cursor = reads.find_or_initialize_by(user: user)
        cursor.last_message_id = [cursor.last_message_id || 0, messages.where('id <= ?', message_id.to_i).maximum(:id) || 0].max
        cursor.save!
      end
    end
  end
end
