module Whatsapp
  class ConversationsController < BaseController
    PER_PAGE = 50
    UNREAD_SQL = <<~SQL.squish.freeze
      EXISTS (SELECT 1 FROM whatsapp_messages m WHERE m.conversation_id = whatsapp_conversations.id
        AND m.direction = 'incoming' AND m.historical = FALSE AND m.id > COALESCE(
          (SELECT r.last_message_id FROM whatsapp_reads r
            WHERE r.conversation_id = whatsapp_conversations.id AND r.user_id = :uid), 0))
    SQL

    before_action :set_client
    before_action :set_campaign, only: :index

    def index
      @connections = scoped_connections.order(:name).to_a
      respond_to do |format|
        format.html
        format.json { render json: list_payload }
      end
    end

    def show
      render json: details(attendance_conversations.find(params[:id]))
    end

    def create
      connection = attendance_connections.find(params.require(:connection_id))
      phone = Phone.normalize(params.require(:phone))
      raise ArgumentError, 'Informe o telefone com DDI e DDD.' unless phone

      conversation = connection.with_lock do
        contact = Contact.resolve!(connection, { 'remoteJid' => "#{phone.delete_prefix('+')}@s.whatsapp.net" })
        connection.conversations.find_or_create_by!(contact: contact)
      end
      render json: summary(conversation), status: :created
    end

    def update
      conversation = attendance_conversations.find(params[:id])
      state = { 'close' => 'closed', 'reopen' => 'open' }[params.require(:operation)]
      raise ArgumentError, 'Ação inválida.' unless state

      conversation.update!(state: state)
      render json: details(conversation)
    end

    def read
      conversation = attendance_conversations.find(params[:id])
      conversation.mark_read!(current_user, params.require(:last_message_id))
      head :no_content
    end

    # Pausar/retomar a resposta automática nesta conversa.
    def auto_reply
      conversation = attendance_conversations.find(params[:id])
      paused = params.fetch(:paused)
      raise ArgumentError, 'Valor inválido.' if paused.nil? || paused.to_s.strip.empty?

      conversation.update!(auto_reply_paused: ActiveModel::Type::Boolean.new.cast(paused))
      render json: details(conversation)
    end

    private

    # Filtro "conversas desta automação": números da automação, ainda dentro dos visíveis ao usuário.
    def set_campaign
      @campaign = @client.campaigns.find(params[:campaign_id]) if @client && params[:campaign_id].present?
    end

    def scoped_connections
      scope = attendance_connections
      scope = scope.where(id: @campaign.whatsapp_connections.select(:id)) if @campaign
      scope
    end

    def list_payload
      visible = attendance_conversations.where(connection_id: @connections.map(&:id))
      scope = visible.includes(:connection, :contact)
      scope = scope.where(connection_id: params[:connection_id]) if params[:connection_id].present?
      scope = scope.where(state: params[:state]) if %w[open closed].include?(params[:state])
      if params[:q].present?
        q = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q].to_s.truncate(100))}%"
        scope = scope.joins(:contact).where('whatsapp_contacts.name ILIKE :q OR whatsapp_contacts.phone ILIKE :q', q: q)
      end
      scope = scope.where(UNREAD_SQL, uid: current_user.id) if params[:unread] == '1'
      page = params[:page].to_i.clamp(1, 1000)
      rows = scope.order(Arel.sql('whatsapp_conversations.last_message_at DESC NULLS LAST'), id: :desc)
                  .limit(PER_PAGE + 1).offset((page - 1) * PER_PAGE).to_a
      shown = rows.first(PER_PAGE)
      checkouts = latest_checkouts(shown.map(&:id))
      unread = visible.where(state: 'open').where(UNREAD_SQL, uid: current_user.id).group(:connection_id).count
      { conversations: shown.map { |c| summary(c, checkouts[c.id]) }, more: rows.length > PER_PAGE,
        connections: @connections.map do |c|
          c.slice(:id, :name, :phone, :state).merge(connected: c.connected?, unread_count: unread[c.id].to_i)
        end }
    end

    # Checkout de recuperação mais recente que falou com cada conversa.
    def latest_checkouts(conversation_ids)
      return {} if conversation_ids.empty?

      @client.abandoned_checkouts.where(whatsapp_conversation_id: conversation_ids)
             .order(:created_at, :id).index_by(&:whatsapp_conversation_id)
    end

    def checkout_payload(checkout)
      return unless checkout

      { status: checkout.status, total_price: checkout.total_price, recovery_url: checkout.recovery_url }
    end

    def summary(c, checkout = latest_checkouts([c.id])[c.id])
      c.slice(:id, :state, :auto_reply_paused, :last_message_at, :last_message_preview).merge(
        name: c.contact.display_name, phone: c.contact.phone, connection_id: c.connection_id,
        connection_name: c.connection.name, connection_phone: c.connection.phone,
        connection_state: c.connection.state, unread_count: c.unread_count(current_user),
        checkout: checkout_payload(checkout)
      )
    end

    def details(c) = summary(c).merge(auto_reply_available: @client.auto_reply_ready?)
  end
end
