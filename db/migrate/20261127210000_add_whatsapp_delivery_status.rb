# Status de entrega que a Meta devolve pelo webhook da API Oficial (enviada, entregue, lida ou falhou + motivo)
# e o nome de quem abandonou o checkout (vai no {{1}} do modelo; o checkout quase nunca tem cliente vinculado).
class AddWhatsappDeliveryStatus < ActiveRecord::Migration[7.2]
  def change
    change_table :abandoned_checkouts, bulk: true do |t|
      t.string :whatsapp_message_id
      t.string :whatsapp_status
      t.datetime :whatsapp_status_at
      t.string :whatsapp_error
      t.string :customer_name
      t.index :whatsapp_message_id
    end

    change_table :campaign_recipients, bulk: true do |t|
      t.string :delivery_status
      t.datetime :delivery_status_at
      t.string :delivery_error
      t.index :provider_message_id
    end
  end
end
