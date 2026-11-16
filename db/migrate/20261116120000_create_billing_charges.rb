class CreateBillingCharges < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :billing_document, :string
    add_column :clients, :asaas_customer_id, :string

    create_table :billing_charges do |t|
      t.references :client, null: false, foreign_key: true
      t.date :month, null: false
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.date :due_date
      t.string :status, null: false, default: 'pending'
      t.string :asaas_payment_id
      t.string :invoice_url
      t.text :error_message
      t.timestamps
    end
    add_index :billing_charges, %i[client_id month], unique: true
  end
end
