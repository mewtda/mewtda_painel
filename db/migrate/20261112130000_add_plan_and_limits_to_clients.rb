class AddPlanAndLimitsToClients < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :plan_name, :string
    add_column :clients, :plan_price, :decimal, precision: 10, scale: 2
    # nil = sem limite
    add_column :clients, :daily_whatsapp_limit, :integer
    add_column :clients, :daily_email_limit, :integer
  end
end
