class AddDispatchFieldsToCampaigns < ActiveRecord::Migration[7.2]
  def change
    add_column :campaigns, :next_run_at, :datetime
    add_column :campaigns, :published_at, :datetime
    add_column :campaigns, :acknowledged_not_subscribed, :integer
    add_reference :campaigns, :published_by, foreign_key: { to_table: :users, on_delete: :nullify }
    add_index :campaigns, %i[status next_run_at]
  end
end
