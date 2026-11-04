module Whatsapp
  class BaseController < ApplicationController
    include ClientScoped

    before_action :private_response
    rescue_from JSON::ParserError, with: -> { render json: { error: 'Parâmetros inválidos.' }, status: :unprocessable_entity }
    rescue_from ActiveRecord::RecordNotFound, with: -> { head :not_found }
    rescue_from ActiveRecord::RecordInvalid, Media::Invalid, ArgumentError, ActionController::ParameterMissing do |error|
      message = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(', ') : error.message
      render json: { error: message }, status: :unprocessable_entity
    end

    private

    def private_response
      response.headers['Cache-Control'] = 'no-store, private'
      response.headers['X-Content-Type-Options'] = 'nosniff'
    end

    def require_management
      head :forbidden unless Connection.administrable_by?(current_user)
    end

    # Gestão: cliente da URL. Telas de conversa usam o cliente selecionado (ClientScoped).
    def current_whatsapp_client
      @current_whatsapp_client ||=
        params[:client_id] ? Client.find(params[:client_id]) : Client.find(current_client_id)
    end

    def authorized_connections = Connection.visible_to(current_user, client: current_whatsapp_client)

    # Atendimento: sempre o cliente selecionado (ClientScoped#set_client), nunca um client_id da URL.
    # Sem cliente, visible_to não devolve nada e toda conversa vira 404.
    def attendance_connections = Connection.visible_to(current_user, client: @client)
    def attendance_conversations = Conversation.visible_to(current_user, client: @client)
  end
end
