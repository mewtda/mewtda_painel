require 'test_helper'
require Rails.root.join('db/migrate/20261119130000_create_campaign_messages')

class CreateCampaignMessagesTest < ActiveSupport::TestCase
  test 'an old e-mail campaign becomes one e-mail message with the same segment, recipients and numbers' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    template = EmailTemplate.create!(client:, name: 'Modelo', subject: 'Oi', blocks: [{ 'type' => 'heading', 'text' => 'Oi' }])
    segment = client.segments.create!(name: 'Todos', kind: 'static')
    published = Time.zone.local(2026, 11, 10, 9, 0)
    campaign = client.campaigns.create!(name: 'Antiga', email_template_id: template.id, segment_id: segment.id,
                                        status: 'sent', send_mode: 'now', published_at: published,
                                        audience_frozen_at: published, recipients_count: 2, sent_count: 1,
                                        failed_count: 1, started_at: published, finished_at: published + 1.hour)
    conn = ActiveRecord::Base.connection
    %w[ana@example.com bia@example.com].each_with_index do |email, i|
      conn.execute(<<~SQL.squish)
        INSERT INTO campaign_recipients (campaign_id, email, status, created_at, updated_at)
        VALUES (#{campaign.id}, '#{email}', '#{i.zero? ? 'sent' : 'failed'}', now(), now())
      SQL
    end

    CreateCampaignMessages.new.copy_existing_campaigns

    campaign.reload
    message = campaign.messages.sole
    assert_equal [segment.id], campaign.segment_ids
    assert_equal ['email', template.id, 'sent', published], [message.channel, message.email_template_id, message.status, message.send_at]
    assert_equal [2, 1, 1, 0], [message.recipients_count, message.sent_count, message.failed_count, message.blocked_count]
    assert_equal [published, published + 1.hour], [message.started_at, message.finished_at]
    assert_equal [message.id] * 2, campaign.recipients.pluck(:campaign_message_id)
    assert_equal %w[email email], campaign.recipients.pluck(:channel)

    CreateCampaignMessages.new.copy_existing_campaigns
    assert_equal 1, campaign.messages.count, 'running the copy twice must not duplicate'
  end
end
