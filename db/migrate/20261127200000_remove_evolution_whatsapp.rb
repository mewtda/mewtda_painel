# A Evolution API saiu do painel: o WhatsApp agora é só a API Oficial (Cloud API da Meta).
# Apaga os números conectados por QR, as conversas, mensagens, mídias e a resposta automática com IA.
# Irreversível: o histórico de conversas da Evolution não volta.
class RemoveEvolutionWhatsapp < ActiveRecord::Migration[7.2]
  TABLES = %i[
    whatsapp_automation_connections whatsapp_reads whatsapp_memberships whatsapp_receipts whatsapp_events
    whatsapp_media whatsapp_messages whatsapp_conversations whatsapp_contact_aliases whatsapp_contacts
    whatsapp_connections
  ].freeze

  def up
    remove_reference :abandoned_checkouts, :whatsapp_conversation, foreign_key: { to_table: :whatsapp_conversations }
    remove_reference :abandoned_checkouts, :whatsapp_connection, foreign_key: { to_table: :whatsapp_connections }
    TABLES.each { |table| drop_table table, force: :cascade }

    remove_column :automations, :evolution_started_at
    remove_column :clients, :whatsapp_provider
    remove_column :clients, :auto_reply_enabled
    remove_column :clients, :openai_api_key
    remove_column :clients, :openai_model
    remove_column :clients, :auto_reply_instructions
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'a Evolution foi removida; os dados apagados não voltam'
  end
end
