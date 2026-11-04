class CreateWhatsappCampaignConnections < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_campaign_connections do |t|
      t.references :campaign, null: false, foreign_key: true
      t.references :connection, null: false, foreign_key: { to_table: :whatsapp_connections }
      t.datetime :last_assigned_at
      t.timestamps
    end
    add_index :whatsapp_campaign_connections, %i[campaign_id connection_id], unique: true, name: 'idx_wa_campaign_connection_unique'
    add_column :campaigns, :evolution_started_at, :datetime
  end
end
