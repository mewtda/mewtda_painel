# Cashback e rastreio enviavam pelos números da Evolution, que saiu do painel. Enquanto não passam a usar
# modelos aprovados da API Oficial, o envio (inclusive o reenvio manual) marca a ação como falha.
class SendAutomationNotificationJob < ApplicationJob
  queue_as :default

  DISABLED_REASON = 'Envio por WhatsApp desativado: só a recuperação de carrinho usa a API Oficial'.freeze

  def perform(automation_action_id, _extra = {})
    AutomationAction.find_by(id: automation_action_id)&.mark_as_failed!(DISABLED_REASON)
  end
end
