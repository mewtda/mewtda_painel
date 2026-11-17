class CreateConversionInsights < ActiveRecord::Migration[7.2]
  def change
    create_table :conversion_insights do |t|
      t.references :client, null: false, foreign_key: true
      t.date :week_start, null: false
      t.text :body, null: false
      t.jsonb :metrics, null: false, default: {}
      t.string :model
      t.timestamps
    end
    add_index :conversion_insights, %i[client_id week_start], unique: true
  end
end
