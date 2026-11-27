# Mensagem de cashback (compra e cupom expirando). Desativada junto com o cashback: enviava pelos números
# da Evolution, que saiu do painel (ver ProcessCashbackAutomationsJob::DISABLED).
class CustomerNotificationJob < ApplicationJob
  queue_as :default

  def perform(_order_id, _coupon_code, _type); end
end
