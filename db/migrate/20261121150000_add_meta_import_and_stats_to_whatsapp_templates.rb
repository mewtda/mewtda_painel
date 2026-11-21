# Modelos importados da conta do WhatsApp conectada (criados direto na Meta) e números da Meta por modelo
# (enviadas, entregues, lidas e cliques, da análise de modelos da Meta).
class AddMetaImportAndStatsToWhatsappTemplates < ActiveRecord::Migration[7.2]
  def change
    change_table :whatsapp_templates, bulk: true do |t|
      t.string :header_text
      t.boolean :imported, null: false, default: false
      t.string :unsupported_reason
      t.integer :stats_sent, null: false, default: 0
      t.integer :stats_delivered, null: false, default: 0
      t.integer :stats_read, null: false, default: 0
      t.integer :stats_clicked, null: false, default: 0
      t.datetime :stats_synced_at
    end
  end
end
