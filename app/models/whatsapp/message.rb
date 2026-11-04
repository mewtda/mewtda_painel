module Whatsapp
  class Message < ApplicationRecord
    ORIGINS = %w[team automation ai phone].freeze
    PREVIEWS = { 'image' => 'Imagem', 'document' => 'Documento', 'audio' => 'Áudio',
                 'video' => 'Vídeo', 'sticker' => 'Figurinha' }.freeze

    belongs_to :connection
    belongs_to :conversation
    belongs_to :user, optional: true
    has_one :media, class_name: 'Whatsapp::Media', dependent: :restrict_with_exception
    validates :direction, inclusion: { in: %w[incoming outgoing] }
    validates :kind, inclusion: { in: %w[text image document audio video sticker unsupported] }
    validates :origin, inclusion: { in: ORIGINS }
    validates :body, length: { maximum: 10_000 }
    validate { errors.add(:conversation, 'de outro número') if conversation && conversation.connection_id != connection_id }

    def author_name
      case origin
      when 'ai' then 'Resposta automática'
      when 'automation' then 'Automação'
      else user&.name
      end
    end

    def preview = body.presence || PREVIEWS.fetch(kind, 'Mensagem não suportada')

    def apply_receipt!(rank)
      return unless direction == 'outgoing' && rank.to_i > receipt_rank

      update!(receipt_rank: rank, state: { 1 => 'sent', 2 => 'delivered', 3 => 'read' }.fetch(rank.to_i))
    end
  end
end
