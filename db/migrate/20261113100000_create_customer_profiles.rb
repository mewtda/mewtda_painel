class CreateCustomerProfiles < ActiveRecord::Migration[7.2]
  def change
    # Visão do cliente por loja (customers é global; o vínculo com a loja vem
    # dos pedidos). Recalculada por Customers::RefreshProfiles a partir de orders.
    create_table :customer_profiles do |t|
      t.references :client, null: false, foreign_key: true
      t.references :customer, null: false, foreign_key: true
      t.string :name
      t.string :email
      t.string :phone
      t.string :city
      t.string :state
      t.integer :orders_count, null: false, default: 0
      t.decimal :total_spent, precision: 12, scale: 2, null: false, default: 0
      t.decimal :avg_ticket, precision: 12, scale: 2, null: false, default: 0
      t.decimal :last_order_total, precision: 12, scale: 2
      t.integer :coupons_used, null: false, default: 0
      t.datetime :first_order_at
      t.datetime :last_order_at
      t.integer :r_score
      t.integer :f_score
      t.integer :m_score
      t.string :rfm_segment
      t.datetime :refreshed_at, null: false
      t.timestamps
    end

    add_index :customer_profiles, %i[client_id customer_id], unique: true
    add_index :customer_profiles, %i[client_id rfm_segment]
    add_index :customer_profiles, %i[client_id last_order_at]
    add_index :customer_profiles, %i[client_id total_spent]
  end
end
