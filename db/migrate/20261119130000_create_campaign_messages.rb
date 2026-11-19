# Campanha passa a ter vários segmentos e várias mensagens (e-mail e WhatsApp), cada uma com data/hora.
# As campanhas existentes viram uma campanha com uma mensagem de e-mail; os destinatários apontam para ela.
# Os campos antigos (email_template_id, segment_id, send_mode, scheduled_at, janela) ficam por enquanto.
class CreateCampaignMessages < ActiveRecord::Migration[7.2]
  def up
    create_table :campaign_segments do |t|
      t.references :campaign, null: false, foreign_key: { on_delete: :cascade }
      t.references :segment, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :campaign_segments, %i[campaign_id segment_id], unique: true

    add_column :campaigns, :email_enabled, :boolean, null: false, default: true
    add_column :campaigns, :whatsapp_enabled, :boolean, null: false, default: false

    create_table :campaign_messages do |t|
      t.references :campaign, null: false, foreign_key: { on_delete: :cascade }
      t.string :channel, null: false, default: 'email'
      t.references :email_template, foreign_key: { on_delete: :nullify }
      t.references :whatsapp_template, foreign_key: { on_delete: :nullify }
      t.datetime :send_at
      t.integer :position, null: false, default: 0
      t.string :status, null: false, default: 'draft'
      t.string :note
      t.datetime :next_run_at
      t.datetime :audience_frozen_at
      t.integer :recipients_count
      t.integer :sent_count, null: false, default: 0
      t.integer :failed_count, null: false, default: 0
      t.integer :blocked_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end
    add_index :campaign_messages, %i[status next_run_at]

    add_reference :campaign_recipients, :campaign_message, foreign_key: { on_delete: :cascade }
    add_column :campaign_recipients, :channel, :string, null: false, default: 'email'
    add_column :campaign_recipients, :phone, :string
    add_column :campaign_recipients, :provider_message_id, :string
    change_column_null :campaign_recipients, :email, true
    remove_index :campaign_recipients, %i[campaign_id email]
    add_index :campaign_recipients, %i[campaign_message_id email], unique: true, where: "channel = 'email'",
                                                                     name: 'index_campaign_recipients_unique_email'
    add_index :campaign_recipients, %i[campaign_message_id phone], unique: true, where: "channel = 'whatsapp'",
                                                                     name: 'index_campaign_recipients_unique_phone'
    add_index :campaign_recipients, %i[campaign_message_id status]

    copy_existing_campaigns
  end

  def down
    remove_index :campaign_recipients, name: 'index_campaign_recipients_unique_email'
    remove_index :campaign_recipients, name: 'index_campaign_recipients_unique_phone'
    execute "DELETE FROM campaign_recipients WHERE channel <> 'email'"
    remove_reference :campaign_recipients, :campaign_message, foreign_key: true, index: true
    remove_column :campaign_recipients, :channel
    remove_column :campaign_recipients, :phone
    remove_column :campaign_recipients, :provider_message_id
    change_column_null :campaign_recipients, :email, false
    add_index :campaign_recipients, %i[campaign_id email], unique: true
    drop_table :campaign_messages
    remove_column :campaigns, :email_enabled
    remove_column :campaigns, :whatsapp_enabled
    drop_table :campaign_segments
  end

  # Idempotente: só copia campanhas que ainda não têm mensagens.
  def copy_existing_campaigns
    execute <<~SQL.squish
      INSERT INTO campaign_segments (campaign_id, segment_id, created_at, updated_at)
      SELECT c.id, c.segment_id, now(), now() FROM campaigns c
      WHERE c.segment_id IS NOT NULL
      ON CONFLICT (campaign_id, segment_id) DO NOTHING
    SQL
    execute <<~SQL.squish
      INSERT INTO campaign_messages (campaign_id, channel, email_template_id, send_at, position, status, next_run_at,
                                     audience_frozen_at, recipients_count, sent_count, failed_count, blocked_count,
                                     started_at, finished_at, created_at, updated_at)
      SELECT c.id, 'email', c.email_template_id,
             CASE WHEN c.send_mode = 'scheduled' THEN c.scheduled_at ELSE c.published_at END,
             0, c.status, c.next_run_at, c.audience_frozen_at, c.recipients_count, c.sent_count, c.failed_count,
             c.blocked_count, c.started_at, c.finished_at, now(), now()
      FROM campaigns c
      WHERE NOT EXISTS (SELECT 1 FROM campaign_messages m WHERE m.campaign_id = c.id)
    SQL
    execute <<~SQL.squish
      UPDATE campaign_recipients r SET campaign_message_id = m.id, channel = 'email'
      FROM campaign_messages m
      WHERE m.campaign_id = r.campaign_id AND m.channel = 'email' AND r.campaign_message_id IS NULL
        AND m.id = (SELECT MIN(id) FROM campaign_messages WHERE campaign_id = r.campaign_id)
    SQL
  end
end
