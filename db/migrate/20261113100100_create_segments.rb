class CreateSegments < ActiveRecord::Migration[7.2]
  def change
    create_table :segments do |t|
      t.references :client, null: false, foreign_key: true
      t.string :name, null: false
      t.string :description
      t.string :kind, null: false, default: 'dynamic' # dynamic (regras) | static (lista)
      t.jsonb :rules, null: false, default: {}
      t.integer :customers_count
      t.datetime :counted_at
      t.timestamps
    end

    create_table :segment_memberships do |t|
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }
      t.references :customer, null: false, foreign_key: true
      t.timestamps
    end
    add_index :segment_memberships, %i[segment_id customer_id], unique: true
  end
end
