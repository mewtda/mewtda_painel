module Whatsapp
  class MessagesController < BaseController
    INLINE_KINDS = %w[image audio video sticker].freeze

    before_action :set_client
    before_action :set_conversation

    def index
      scope = @conversation.messages.includes(:user, :media)
      if params[:after_id].present?
        fresh = scope.where('id > ?', params[:after_id].to_i).order(:id).limit(100).to_a
        known = scope.where(id: Array(params[:ids]).first(200)).to_a
        rows = (fresh + known).uniq(&:id)
        render json: { messages: rows.map { |m| payload(m) }, after_id: fresh.last&.id || params[:after_id].to_i,
                       more_new: fresh.length == 100 }
      else
        if params[:before].present?
          time, id = before_cursor
          scope = scope.where('sent_at < :t OR (sent_at = :t AND id < :id)', t: time, id: id)
        end
        rows = scope.order(sent_at: :desc, id: :desc).limit(51).to_a
        page = rows.first(50)
        oldest = page.last
        render json: { messages: page.reverse.map { |m| payload(m) }, after_id: page.map(&:id).max || 0,
                       before: rows.length > 50 ? Base64.urlsafe_encode64([oldest.sent_at.iso8601(6), oldest.id].to_json) : nil }
      end
    end

    def create
      nonce = params.require(:client_nonce).to_s
      raise ArgumentError, 'Identificador de envio inválido.' unless nonce.match?(/\A[a-zA-Z0-9-]{16,64}\z/)

      connection = @conversation.connection
      message = nil
      connection.with_lock do
        message = connection.messages.find_by(client_nonce: nonce)
        if message
          raise ArgumentError, 'Identificador usado em outra conversa.' unless message.conversation_id == @conversation.id
        else
          message = create_team_message!(connection, nonce)
        end
      end
      SendJob.perform_later(message.id) if message.state == 'queued'
      render json: payload(message), status: :accepted
    end

    def retry_send
      message = @conversation.messages.find(params[:id])
      @conversation.connection.with_lock do
        message.reload
        raise ArgumentError, 'Somente uma falha confirmada antes do envio pode ser repetida.' unless message.state == 'failed'

        message.update!(state: 'queued', error_code: nil)
      end
      SendJob.perform_later(message.id)
      render json: payload(message), status: :accepted
    end

    def attachment
      message = @conversation.messages.find(params[:id])
      media = message.media || raise(ActiveRecord::RecordNotFound)
      # Rota privada, autorizada a cada pedido. Nenhum ID de blob ou URL remota sai do servidor.
      send_data media.download, type: media.content_type, filename: media.filename,
                                disposition: INLINE_KINDS.include?(message.kind) ? 'inline' : 'attachment'
    end

    private

    def set_conversation = @conversation = attendance_conversations.find(params[:conversation_id])

    def create_team_message!(connection, nonce)
      body = params[:body].to_s
      upload = params[:file].presence
      raise ArgumentError, 'Escreva uma mensagem ou selecione um arquivo.' if body.blank? && upload.blank?
      raise ArgumentError, 'A mensagem deve ter até 10.000 caracteres.' if body.length > 10_000
      raise ArgumentError, 'Este número precisa ser conectado antes do envio.' unless connection.connected?

      if upload
        _, kind = Media.inspect_upload(upload.tempfile, filename: upload.original_filename)
        raise ArgumentError, 'Áudios não aceitam legenda. Envie o texto em uma mensagem separada.' if kind == 'audio' && body.present?
      end
      message = @conversation.messages.create!(connection: connection, user: current_user, origin: 'team',
                                               client_nonce: nonce, body: body, direction: 'outgoing',
                                               state: 'queued', sent_at: Time.current)
      Media.store!(message, upload.tempfile, filename: upload.original_filename) if upload
      @conversation.update!(last_message_at: message.sent_at, last_message_preview: message.preview.truncate(180))
      # Resposta da equipe pausa a resposta automática nesta conversa.
      @conversation.team_replied!
      message
    end

    # Cursor opaco do histórico: [sent_at ISO8601, id] em Base64.
    def before_cursor
      cursor = JSON.parse(Base64.urlsafe_decode64(params[:before].to_s))
      unless cursor.is_a?(Array) && cursor.length == 2 && cursor[0].is_a?(String) && cursor[1].is_a?(Integer) && cursor[1].positive?
        raise ArgumentError, 'Página de histórico inválida.'
      end

      [Time.iso8601(cursor[0]), cursor[1]]
    end

    def payload(message)
      message.slice(:id, :body, :kind, :direction, :state, :origin, :sent_at, :media_state, :client_nonce).merge(
        author: message.author_name, filename: message.media&.filename,
        media_url: message.media ? attachment_whatsapp_conversation_message_path(@conversation, message) : nil
      )
    end
  end
end
