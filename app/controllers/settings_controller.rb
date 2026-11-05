class SettingsController < ApplicationController
  before_action :set_client

  def edit; end

  def update
    %i[meta_access_token shopify_access_token shopify_storefront_token
       whatsapp_cloud_access_token].each do |secret|
      params[:client].delete(secret) if params[:client][secret].blank?
    end

    if @client.update(client_params)
      redirect_to edit_settings_path, notice: 'Configurações atualizadas com sucesso.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_client
    @client = current_user.client

    unless @client
      redirect_to crm_path, alert: 'Você não está vinculado a nenhum cliente.'
    end
  end

  def client_params
    params.require(:client).permit(
      :name, :email, :shopify_shop_url, :shopify_access_token, :shopify_storefront_token,
      :whatsapp_cloud_phone_number_id, :whatsapp_cloud_business_account_id, :whatsapp_cloud_access_token,
      :meta_access_token, :meta_ad_account_id,
      :google_ads_customer_id
    )
  end
end
