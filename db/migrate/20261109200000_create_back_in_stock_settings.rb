class CreateBackInStockSettings < ActiveRecord::Migration[7.2]
  def change
    create_table :back_in_stock_settings do |t|
      t.references :client, null: false, foreign_key: true, index: { unique: true }
      t.boolean :active, null: false, default: true
      t.string  :public_token, null: false, index: { unique: true }
      t.string  :button_text, null: false, default: 'Me avise quando voltar ao estoque'
      t.string  :modal_title, null: false, default: 'Avise-me quando chegar'
      t.string  :accent_color, null: false, default: '#111111'
      t.timestamps
    end
  end
end
