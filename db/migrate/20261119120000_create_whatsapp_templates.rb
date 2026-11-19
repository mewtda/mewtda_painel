class CreateWhatsappTemplates < ActiveRecord::Migration[7.2]
  def change
    create_table :whatsapp_templates do |t|
      t.references :client, null: false, foreign_key: true
      t.string :name, null: false
      t.string :label, null: false
      t.string :category, null: false, default: 'MARKETING'
      t.string :language, null: false, default: 'pt_BR'
      t.text :body, null: false
      t.string :body_example
      t.string :footer
      t.string :button_text
      t.string :button_url
      t.string :meta_id
      t.string :status, null: false, default: 'draft'
      t.string :rejection_reason
      t.datetime :synced_at
      t.timestamps
    end
    add_index :whatsapp_templates, %i[client_id name], unique: true
    add_index :whatsapp_templates, %i[client_id status]
  end
end
