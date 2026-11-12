class CreateBackInStockAlerts < ActiveRecord::Migration[7.2]
  def change
    create_table :back_in_stock_alerts do |t|
      t.references :client, null: false, foreign_key: true, index: false
      t.bigint   :shopify_product_id, null: false
      t.bigint   :shopify_variant_id, null: false
      t.bigint   :shopify_customer_id
      t.string   :product_handle, null: false
      t.string   :product_title
      t.string   :variant_title
      t.string   :sku
      t.decimal  :price, precision: 10, scale: 2
      t.string   :image_url
      t.string   :email, null: false
      t.string   :phone
      t.string   :status, null: false, default: 'pending'
      t.datetime :notified_at
      t.datetime :consented_at, null: false
      t.timestamps
    end

    add_index :back_in_stock_alerts, 'client_id, shopify_variant_id, lower(email)',
              unique: true, where: "status = 'pending'", name: 'idx_bis_alerts_pending_unique'
    add_index :back_in_stock_alerts, %i[client_id status]
    add_index :back_in_stock_alerts, %i[status client_id product_handle], name: 'idx_bis_alerts_restock'
  end
end
