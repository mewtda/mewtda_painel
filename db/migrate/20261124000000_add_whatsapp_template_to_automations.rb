class AddWhatsappTemplateToAutomations < ActiveRecord::Migration[7.2]
  # Recuperação de carrinho pela API Oficial: com um modelo escolhido, a 1ª mensagem sai como esse modelo
  # aprovado na Meta em vez de texto livre pela Evolution.
  def change
    add_reference :automations, :whatsapp_template, null: true, foreign_key: { on_delete: :nullify }
  end
end
