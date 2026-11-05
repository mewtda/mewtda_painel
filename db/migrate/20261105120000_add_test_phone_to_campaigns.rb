class AddTestPhoneToCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :campaigns, :test_phone, :string
  end
end
