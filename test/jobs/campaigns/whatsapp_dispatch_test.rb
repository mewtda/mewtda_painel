require 'test_helper'

class WhatsappDispatchTest < ActiveJob::TestCase
  MONDAY = Time.zone.local(2026, 11, 16, 10, 0)

  class FakeApi
    attr_reader :calls

    def initialize(failing: {})
      @failing = failing
      @calls = []
    end

    def configured? = true

    def send_template(to:, **args)
      raise @failing[to] if @failing[to]

      @calls << { to:, **args }
      "wamid.#{@calls.size}"
    end
  end

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                             whatsapp_cloud_access_token: 't')
    @segment = @client.segments.create!(name: 'Lista', kind: 'static')
    @template = @client.whatsapp_templates.create!(label: 'Black', body: 'Oi {{1}}, a Black chegou', body_example: 'Maria',
                                                   status: 'approved')
    @campaign = @client.campaigns.create!(name: 'Black', segment_ids: [@segment.id], whatsapp_enabled: true,
                                          email_enabled: false, status: 'scheduled')
    @message = @campaign.messages.create!(channel: 'whatsapp', whatsapp_template: @template, status: 'scheduled',
                                          next_run_at: 1.minute.ago)
  end

  def person(name, phone)
    customer = Customer.create!(first_name: name.to_s.split.first, email: "#{SecureRandom.hex(4)}@example.com",
                                shopify_customer_id: SecureRandom.hex(6))
    CustomerProfile.create!(client: @client, customer:, name:, phone:, refreshed_at: Time.current)
    SegmentMembership.create!(segment: @segment, customer:)
  end

  def run_job(api = FakeApi.new)
    job = Campaigns::DispatchJob.new
    job.stub(:throttle, 0) do
      Whatsapp::Cloud::Api.stub(:new, ->(_client) { api }) { job.perform(@message.id) }
    end
    api
  end

  test 'sends the approved template to each person with the first name' do
    person('Ana Souza', '(16) 99237-5432')
    person('Bia', '31990131953')
    person(nil, '+5511988887777')

    api = run_job
    @message.reload

    assert_equal [['+5511988887777', 'cliente'], ['+5516992375432', 'Ana'], ['+5531990131953', 'Bia']],
                 api.calls.map { |c| [c[:to], c[:body_params].first] }.sort
    assert(api.calls.all? { |c| c[:name] == 'black' && c[:language] == 'pt_BR' })
    assert_equal 'sent', @message.status
    assert_equal 3, @message.sent_count
    assert_equal 'wamid.1', @message.recipients.order(:id).first.provider_message_id
    assert_equal 'sent', @campaign.reload.status
    assert_equal 3, @campaign.sent_count
  end

  test 'a template without variable sends no parameters' do
    @template.update_columns(body: 'A Black chegou', body_example: nil)
    person('Ana', '16992375432')
    assert_equal [], run_job.calls.first[:body_params]
  end

  test 'rate limit pauses a minute without marking failures' do
    person('Ana', '16992375432')
    api = FakeApi.new(failing: { '+5516992375432' => Whatsapp::Cloud::Api::RateLimited.new('devagar', code: 130_429) })
    @message.update!(next_run_at: MONDAY - 1.minute)
    travel_to MONDAY do
      run_job(api)
      @message.reload
      assert_equal 'paused', @message.status
      assert_equal MONDAY + 1.minute, @message.next_run_at
      assert_equal 'pending', @message.recipients.sole.status
    end
  end

  test 'blocked by Meta marks the person as blocked, other errors as failed' do
    person('Ana', '16992375432')
    person('Bia', '31990131953')
    person('Caio', '11988887777')
    api = FakeApi.new(failing: { '+5516992375432' => Whatsapp::Cloud::Api::Blocked.new('marketing', code: 131_050),
                                 '+5531990131953' => Whatsapp::Cloud::Api::Error.new('Número inválido', code: 100) })
    run_job(api)
    @message.reload

    assert_equal [1, 1, 1], [@message.sent_count, @message.failed_count, @message.blocked_count]
    assert_equal 'Número inválido', @message.recipients.find_by(phone: '+5531990131953').error
    assert_equal 'sent', @message.status
  end

  test 'a second run does not send again to who already received it' do
    person('Ana', '16992375432')
    run_job
    @message.update!(status: 'sending', next_run_at: 1.minute.ago)
    assert_empty run_job.calls
    assert_equal 1, @message.reload.sent_count
  end

  test 'a template that is no longer approved pauses the message for an hour without calling Meta' do
    person('Ana', '16992375432')
    @template.update!(status: 'paused')
    @message.update!(next_run_at: MONDAY - 1.minute)
    travel_to MONDAY do
      api = run_job
      @message.reload
      assert_empty api.calls
      assert_equal 'paused', @message.status
      assert_equal MONDAY + 1.hour, @message.next_run_at
      assert_match 'aprovado', @message.note
      assert_nil @message.audience_frozen_at
      assert_match 'aprovado', @campaign.reload.status_note(MONDAY)
    end
  end

  test 'without the official API configured the message pauses' do
    person('Ana', '16992375432')
    @client.update!(whatsapp_cloud_access_token: nil)
    api = FakeApi.new
    def api.configured? = false
    run_job(api)
    assert_empty api.calls
    assert_equal 'paused', @message.reload.status
    assert_match 'API Oficial', @message.note
  end

  test 'stops at the daily WhatsApp limit and continues tomorrow at 8am' do
    @message.update!(next_run_at: MONDAY - 1.minute)
    travel_to MONDAY do
      @client.update!(daily_whatsapp_limit: 2)
      person('Ana', '16992375431')
      person('Bia', '16992375432')
      person('Caio', '16992375433')

      api = run_job
      @message.reload
      assert_equal 2, api.calls.size
      assert_equal 'paused', @message.status
      assert_equal Time.zone.local(2026, 11, 17, 8, 0), @message.next_run_at
      assert_equal 2, Billing::Usage.new(@client).today('whatsapp')
    end
  end
end
