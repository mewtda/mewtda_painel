class CreateEmailEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :email_events do |t|
      t.references :client, null: false, foreign_key: true
      t.string :source, null: false
      t.references :campaign, foreign_key: { on_delete: :cascade }
      t.references :campaign_recipient, foreign_key: { on_delete: :cascade }
      t.references :back_in_stock_alert, foreign_key: { on_delete: :cascade }
      t.string :event_type, null: false
      t.string :bounce_type
      t.text :link
      t.string :ses_message_id, null: false
      t.datetime :occurred_at, null: false
      t.datetime :created_at, null: false
    end

    add_index :email_events, "ses_message_id, event_type, occurred_at, COALESCE(link, '')", unique: true,
                                                                                            name: 'index_email_events_uniqueness'
    add_index :email_events, %i[campaign_id event_type]
    add_index :email_events, %i[client_id source event_type occurred_at]
  end
end
