class AccountController < ApplicationController
  include ClientScoped

  INVOICE_MONTHS = 6

  before_action :set_client, only: %i[limits invoice]

  def edit
    @user = current_user
  end

  # Aba "Meus limites": envios de WhatsApp e e-mail de hoje x limite diário.
  def limits
    return unless @client

    @usage = Billing::Usage.new(@client)
    @month_range = Time.zone.today.beginning_of_month..Time.zone.today
  end

  # Aba "Fatura": plano + e-mails enviados no mês escolhido.
  def invoice
    return unless @client

    @months = (0...INVOICE_MONTHS).map { |i| Time.zone.today.beginning_of_month << i }
    month = @months.find { |m| m.strftime('%Y-%m') == params[:mes] } || @months.first
    @invoice = Billing::Invoice.new(@client, month)
  end

  def update
    if current_user.update(account_params)
      redirect_to edit_account_path, notice: 'Dados atualizados com sucesso.'
    else
      @user = current_user
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def account_params
    params.require(:user).permit(:name, :email, :phone, :password, :password_confirmation)
  end
end
