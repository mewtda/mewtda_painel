class RenameCampaignsToAutomations < ActiveRecord::Migration[7.2]
  def change
    rename_table :campaigns, :automations
    rename_table :campaign_actions, :automation_actions
    rename_column :automation_actions, :campaign_id, :automation_id
    rename_table :whatsapp_campaign_connections, :whatsapp_automation_connections
    rename_column :whatsapp_automation_connections, :campaign_id, :automation_id
    rename_index :whatsapp_automation_connections, 'idx_wa_campaign_connection_unique', 'idx_wa_automation_connection_unique'
  end
end
