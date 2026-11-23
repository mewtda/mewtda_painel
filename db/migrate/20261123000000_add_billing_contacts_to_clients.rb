class AddBillingContactsToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :billing_email, :string
    add_column :clients, :billing_phone, :string
  end
end
