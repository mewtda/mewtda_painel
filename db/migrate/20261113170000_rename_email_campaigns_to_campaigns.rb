class RenameEmailCampaignsToCampaigns < ActiveRecord::Migration[7.2]
  def change
    rename_table :email_campaigns, :campaigns
    rename_table :email_campaign_recipients, :campaign_recipients
    rename_column :campaign_recipients, :email_campaign_id, :campaign_id
    add_column :campaigns, :channel, :string, null: false, default: 'email'
  end
end
