class CreateEmailSuppressions < ActiveRecord::Migration[7.2]
  def change
    create_table :email_suppressions do |t|
      t.references :client, null: false, foreign_key: true
      t.string :email, null: false
      t.string :source, null: false, default: 'unsubscribe_link'
      t.timestamps
    end

    add_index :email_suppressions, %i[client_id email], unique: true
  end
end
