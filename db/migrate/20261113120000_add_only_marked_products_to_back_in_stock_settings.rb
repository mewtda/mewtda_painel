class AddOnlyMarkedProductsToBackInStockSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :back_in_stock_settings, :only_marked_products, :boolean, default: false, null: false
  end
end
