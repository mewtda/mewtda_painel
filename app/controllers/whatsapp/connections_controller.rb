module Whatsapp
  class ConnectionsController < BaseController
    before_action :require_management
    before_action :set_connection, only: %i[update destroy connect disconnect sync]

    def index
      connections = current_whatsapp_client.whatsapp_connections.includes(:users).order(:name)
      render json: { connections: connections.map { |c| payload(c) },
                     users: current_whatsapp_client.users.order(:name).map { |u| { id: u.id, name: user_label(u) } },
                     configured: Providers::Evolution.configured? }
    end

    def create
      raise ArgumentError, 'A integração ainda precisa ser configurada pela administração.' unless Providers::Evolution.configured?

      users = permitted_users(params[:user_ids])
      connection = current_whatsapp_client.whatsapp_connections.new(name: params.require(:name))
      Connection.transaction do
        connection.save!
        connection.users = users
      end
      connection.request_control!('connect')
      render json: payload(connection), status: :created
    end

    def update
      users = permitted_users(params[:user_ids])
      @connection.with_lock do
        @connection.update!(name: params.require(:name))
        @connection.users = users
      end
      render json: payload(@connection)
    end

    def destroy
      if @connection.messages.exists?
        return render json: { error: 'Desconecte em vez de excluir: o número tem conversas.' }, status: :unprocessable_entity
      end

      Connection.transaction do
        @connection.memberships.delete_all
        @connection.destroy!
      end
      head :no_content
    rescue ActiveRecord::DeleteRestrictionError
      render json: { error: 'Desconecte em vez de excluir: o número tem histórico.' }, status: :unprocessable_entity
    end

    def connect
      @connection.request_control!('connect')
      render json: payload(@connection), status: :accepted
    end

    def disconnect
      @connection.request_control!('disconnect')
      render json: payload(@connection), status: :accepted
    end

    def sync
      if !@connection.sync_requested_at || @connection.sync_requested_at < 30.seconds.ago
        @connection.update!(sync_requested_at: Time.current)
        SyncJob.perform_later(@connection.id)
      end
      head :accepted
    end

    private

    def set_connection
      @connection = current_whatsapp_client.whatsapp_connections.find(params[:id])
    end

    # Só usuários do próprio cliente podem receber acesso ao número.
    def permitted_users(ids)
      wanted = Array(ids).reject(&:blank?).map(&:to_i).uniq
      users = current_whatsapp_client.users.where(id: wanted).to_a
      raise ArgumentError, 'Selecione somente usuários deste cliente.' unless users.size == wanted.size

      users
    end

    def user_label(user) = user.try(:name).presence || user.email

    def payload(connection)
      connection.slice(:id, :name, :phone, :state, :enabled, :provider_updated_at, :last_synced_at, :error_code).merge(
        qr: connection.current_qr, qr_expires_at: connection.qr_expires_at, user_ids: connection.users.ids
      )
    end
  end
end
