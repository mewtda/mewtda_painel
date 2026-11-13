class CreateEmailCampaigns < ActiveRecord::Migration[7.2]
  def change
    create_table :email_campaigns do |t|
      t.references :client, null: false, foreign_key: true
      t.references :email_template, foreign_key: { on_delete: :nullify }
      t.references :segment, foreign_key: { on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :name, null: false, default: ''
      t.string :status, null: false, default: 'draft'
      t.string :send_mode, null: false, default: 'now'
      t.datetime :scheduled_at
      t.integer :window_days, array: true, null: false, default: []
      t.string :window_from, null: false, default: '08:00'
      t.string :window_to, null: false, default: '12:00'
      t.datetime :audience_frozen_at
      t.integer :recipients_count
      t.integer :sent_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :blocked_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :email_campaigns, %i[client_id status]

    create_table :email_campaign_recipients do |t|
      t.references :email_campaign, null: false, foreign_key: { on_delete: :cascade }
      t.references :customer, foreign_key: { on_delete: :nullify }
      t.string :email, null: false
      t.string :name
      t.string :status, null: false, default: 'pending'
      t.text :error
      t.datetime :sent_at
      t.timestamps
    end

    add_index :email_campaign_recipients, %i[email_campaign_id email], unique: true
    add_index :email_campaign_recipients, %i[email_campaign_id status]
  end
end
