class AddCancelledAtToBackInStockAlerts < ActiveRecord::Migration[7.2]
  def change
    add_column :back_in_stock_alerts, :cancelled_at, :datetime
  end
end
