class ClientsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_client, only: %i[show edit update destroy]
  before_action :require_admin!, except: [:update_selected_client]

  def index
    @clients = Client.order(created_at: :desc).paginate(page: params[:page],
                                                        per_page: params_per_page(params[:per_page]))

    if params[:search].present?
      search_term = "%#{params[:search]}%"
      @clients = @clients.where('name ILIKE ? OR email ILIKE ?', search_term, search_term)
    end

    if params[:status].present?
      @clients = @clients.where(active: params[:status] == 'active')
    end
  end

  def show; end

  def new
    @client = Client.new
  end

  def create
    @client = Client.new(client_params)
    if @client.save
      redirect_to clients_path, notice: 'Cliente criado com sucesso.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    # Os campos de senha vêm sempre vazios no form: em branco = manter o valor atual.
    %i[meta_access_token shopify_access_token shopify_api_secret shopify_storefront_token zapi_instance_token
       zapi_client_token whatsapp_cloud_access_token].each do |secret|
      params[:client].delete(secret) if params[:client][secret].blank?
    end

    if @client.update(client_params)
      redirect_to clients_path, notice: 'Cliente atualizado com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @client.destroy
    redirect_to clients_path, notice: 'Cliente excluído com sucesso.'
  end

  def update_selected_client
    unless current_user.admin?
      return render json: { success: false, error: 'Não autorizado' }, status: :forbidden
    end

    client = Client.find_by(id: params[:client_id], active: true)

    current_user.update(client_id: client&.id)
    if client
      session[:selected_client_id] = client.id
      render json: { success: true, client_name: client.name }
    else
      render json: { success: false, error: 'Cliente não encontrado' }, status: :not_found
    end
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def client_params
    params.require(:client).permit(
      :name, :email, :active, :shopify_shop_url, :shopify_access_token,
      :shopify_api_key, :shopify_api_secret, :shopify_storefront_token, :slug,
      :zapi_instance_id, :zapi_instance_token, :zapi_client_token, :whatsapp_provider,
      :whatsapp_cloud_phone_number_id, :whatsapp_cloud_business_account_id, :whatsapp_cloud_access_token,
      :meta_access_token, :meta_ad_account_id,
      :google_ads_customer_id
    )
  end
end
