class AddMarketingStateAndMergedCustomers < ActiveRecord::Migration[7.2]
  def change
    add_column :customers, :email_marketing_state, :string
    add_column :customer_profiles, :email_marketing_state, :string
    add_column :customer_profiles, :merged_customer_ids, :bigint, array: true, default: [], null: false
    add_column :segments, :subscribed_count, :integer
    add_index :customer_profiles, %i[client_id email_marketing_state]
  end
end
