# Aba "Lista de recusa" do E-mail Marketing: quem pediu pra não receber mais
# e-mails da loja. Nenhum envio via SES sai pra esses endereços.
class EmailSuppressionsController < ApplicationController
  include ClientScoped

  PER_PAGE = 50

  before_action :set_client
  before_action :require_client!

  def index
    scope = @client.email_suppressions.search(params[:q])
    @total = @client.email_suppressions.count
    @page = [params[:page].to_i, 1].max
    @email_suppressions = scope.order(created_at: :desc).offset((@page - 1) * PER_PAGE).limit(PER_PAGE + 1).to_a
    @next_page = @email_suppressions.size > PER_PAGE
    @email_suppressions = @email_suppressions.first(PER_PAGE)
  end

  def create
    email = params.dig(:email_suppression, :email)
    suppression = @client.email_suppressions.new(email:, source: 'manual')
    if suppression.valid?
      EmailSuppression.unsubscribe!(@client, email, source: 'manual')
      redirect_to email_suppressions_path, notice: "#{suppression.email} adicionado à lista de recusa."
    else
      redirect_to email_suppressions_path, alert: suppression.errors.full_messages.to_sentence
    end
  end

  def destroy
    suppression = @client.email_suppressions.find_by(id: params[:id])
    suppression&.destroy
    redirect_to email_suppressions_path(q: params[:q]),
                notice: suppression ? "#{suppression.email} voltou a receber e-mails." : 'Registro não encontrado.'
  end

  private

  def require_client!
    redirect_to crm_path, alert: 'Nenhum cliente selecionado.' unless @client
  end
end
