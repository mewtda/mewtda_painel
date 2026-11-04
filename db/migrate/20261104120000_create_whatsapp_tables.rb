class CreateWhatsappTables < ActiveRecord::Migration[7.2]
  def change
    add_column :clients, :whatsapp_provider, :string, null: false, default: 'zapi'

    create_table :whatsapp_connections do |t|
      t.references :client, null: false, foreign_key: true
      t.string :name, null: false
      t.string :provider, null: false, default: 'evolution'
      t.string :instance_key, null: false
      t.text :webhook_token, null: false
      t.string :phone
      t.string :state, null: false, default: 'disconnected'
      t.boolean :enabled, null: false, default: true
      t.text :qr_data
      t.datetime :qr_expires_at
      t.datetime :provider_updated_at
      t.datetime :last_event_at
      t.datetime :last_synced_at
      t.datetime :sync_requested_at
      t.string :control_action
      t.integer :control_version, null: false, default: 0
      t.string :error_code
      t.datetime :next_send_at
      t.timestamps
      t.index :instance_key, unique: true
    end

    create_table :whatsapp_contacts do |t|
      t.references :connection, null: false, foreign_key: { to_table: :whatsapp_connections }
      t.references :customer, foreign_key: false
      t.string :provider_jid, limit: 191, null: false
      t.string :phone
      t.string :name
      t.timestamps
      t.index %i[connection_id provider_jid], unique: true, name: 'idx_wa_contact_unique'
      t.index :phone
    end

    create_table :whatsapp_contact_aliases do |t|
      t.references :connection, null: false, foreign_key: { to_table: :whatsapp_connections }
      t.references :contact, null: false, foreign_key: { to_table: :whatsapp_contacts }
      t.string :jid, limit: 191, null: false
      t.index %i[connection_id jid], unique: true, name: 'idx_wa_alias_unique'
    end

    create_table :whatsapp_conversations do |t|
      t.references :connection, null: false, foreign_key: { to_table: :whatsapp_connections }
      t.references :contact, null: false, foreign_key: { to_table: :whatsapp_contacts }
      t.string :state, null: false, default: 'open'
      t.datetime :last_message_at
      t.string :last_message_preview
      t.boolean :auto_reply_paused, null: false, default: false
      t.timestamps
      t.index %i[connection_id contact_id], unique: true, name: 'idx_wa_conversation_unique'
      t.index %i[connection_id last_message_at], name: 'idx_wa_inbox'
    end

    create_table :whatsapp_messages do |t|
      t.references :connection, null: false, foreign_key: { to_table: :whatsapp_connections }
      t.references :conversation, null: false, foreign_key: { to_table: :whatsapp_conversations }
      t.references :user, foreign_key: true
      t.string :provider_id, limit: 191
      t.string :client_nonce, limit: 64
      t.string :direction, null: false
      t.string :kind, null: false, default: 'text'
      t.text :body
      t.string :state, null: false
      t.integer :receipt_rank, null: false, default: 0
      t.boolean :historical, null: false, default: false
      t.datetime :sent_at, null: false
      t.datetime :attempted_at
      t.string :error_code
      t.string :media_state
      t.integer :media_attempts, null: false, default: 0
      t.datetime :media_retry_at
      t.jsonb :provider_key
      t.string :origin, null: false, default: 'team'
      t.datetime :send_after
      t.timestamps
      t.index %i[connection_id client_nonce], unique: true, name: 'idx_wa_client_message'
      t.index %i[connection_id provider_id], unique: true, name: 'idx_wa_provider_message'
      t.index %i[conversation_id sent_at id], name: 'idx_wa_history'
      t.index %i[media_state media_retry_at], name: 'idx_wa_pending_media'
      t.index %i[state attempted_at], name: 'idx_wa_pending_sends'
    end

    create_table :whatsapp_media do |t|
      t.references :message, null: false, foreign_key: { to_table: :whatsapp_messages }, index: { unique: true }
      t.string :storage_key, null: false
      t.string :service_name, null: false
      t.string :filename, null: false
      t.string :content_type, null: false
      t.bigint :byte_size, null: false
      t.timestamps
      t.index :storage_key, unique: true
    end

    create_table :whatsapp_events do |t|
      t.references :connection, null: false, foreign_key: { to_table: :whatsapp_connections }
      t.string :digest, limit: 64, null: false
      t.string :kind, null: false
      t.text :payload, null: false
      t.datetime :occurred_at, null: false
      t.datetime :processed_at
      t.integer :attempts, null: false, default: 0
      t.string :error_code
      t.timestamps
      t.index %i[connection_id digest], unique: true, name: 'idx_wa_event_unique'
      t.index %i[processed_at attempts], name: 'idx_wa_pending_events'
    end

    create_table :whatsapp_receipts do |t|
      t.references :connection, null: false, foreign_key: { to_table: :whatsapp_connections }
      t.string :provider_id, limit: 191, null: false
      t.integer :rank, null: false, default: 0
      t.timestamps
      t.index %i[connection_id provider_id], unique: true, name: 'idx_wa_receipt_unique'
    end

    create_table :whatsapp_memberships do |t|
      t.references :connection, null: false, foreign_key: { to_table: :whatsapp_connections }
      t.references :user, null: false, foreign_key: true
      t.timestamps
      t.index %i[connection_id user_id], unique: true, name: 'idx_wa_membership_unique'
    end

    create_table :whatsapp_reads do |t|
      t.references :conversation, null: false, foreign_key: { to_table: :whatsapp_conversations }
      t.references :user, null: false, foreign_key: true
      t.bigint :last_message_id, null: false, default: 0
      t.index %i[conversation_id user_id], unique: true, name: 'idx_wa_read_unique'
    end
  end
end
