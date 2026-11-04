class AddWhatsappChannelToAbandonedCheckouts < ActiveRecord::Migration[7.2]
  def change
    add_column :abandoned_checkouts, :whatsapp_provider, :string
    add_column :abandoned_checkouts, :skip_reason, :string
    add_reference :abandoned_checkouts, :whatsapp_connection, foreign_key: { to_table: :whatsapp_connections, on_delete: :nullify }
    add_reference :abandoned_checkouts, :whatsapp_conversation, foreign_key: { to_table: :whatsapp_conversations, on_delete: :nullify }
  end
end
