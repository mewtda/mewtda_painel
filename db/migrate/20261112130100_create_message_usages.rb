class CreateMessageUsages < ActiveRecord::Migration[7.2]
  def change
    # Contador diário de envios por canal (hoje só e-mail; o WhatsApp é contado
    # direto em whatsapp_messages).
    create_table :message_usages do |t|
      t.references :client, null: false, foreign_key: true
      t.string :channel, null: false
      t.date :day, null: false
      t.integer :count, null: false, default: 0
      t.timestamps
    end

    add_index :message_usages, %i[client_id channel day], unique: true
  end
end
