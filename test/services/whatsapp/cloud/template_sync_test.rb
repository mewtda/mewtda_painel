require 'test_helper'

class Whatsapp::Cloud::TemplateSyncTest < ActiveSupport::TestCase
  test 'updates status and rejection reason by name' do
    client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                            whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                            whatsapp_cloud_access_token: 't')
    ok = client.whatsapp_templates.create!(label: 'Um', body: 'Oi', status: 'pending')
    bad = client.whatsapp_templates.create!(label: 'Dois', body: 'Oi', status: 'pending')
    api = Object.new
    def api.templates
      [{ 'name' => 'um', 'status' => 'APPROVED', 'id' => '10' },
       { 'name' => 'dois', 'status' => 'REJECTED', 'rejected_reason' => 'PROMOTIONAL', 'id' => '11' }]
    end
    Whatsapp::Cloud::Api.stub(:new, api) { Whatsapp::Cloud::TemplateSync.new(client).call }

    assert_equal 'approved', ok.reload.status
    assert_equal '10', ok.meta_id
    assert_equal 'rejected', bad.reload.status
    assert_equal 'PROMOTIONAL', bad.rejection_reason
    assert bad.synced_at
  end
end
