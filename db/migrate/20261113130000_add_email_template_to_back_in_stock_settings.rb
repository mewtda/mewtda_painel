class AddEmailTemplateToBackInStockSettings < ActiveRecord::Migration[7.2]
  def change
    add_reference :back_in_stock_settings, :email_template, foreign_key: { on_delete: :nullify }, null: true
  end
end
