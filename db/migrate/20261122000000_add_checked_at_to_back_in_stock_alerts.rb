class AddCheckedAtToBackInStockAlerts < ActiveRecord::Migration[7.2]
  def change
    add_column :back_in_stock_alerts, :checked_at, :datetime
  end
end
