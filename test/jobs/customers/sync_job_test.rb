require 'test_helper'

class Customers::SyncJobTest < ActiveJob::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             shopify_shop_url: 'loja.myshopify.com', shopify_access_token: 'token')
    @job = Customers::SyncJob.new
  end

  def shopify(id, **attrs)
    { 'id' => id, 'first_name' => 'Ana', 'email' => "c#{id}@example.com", 'tags' => 'lead-lp, VIP',
      'updated_at' => '2026-11-18T10:00:00-03:00', **attrs.transform_keys(&:to_s) }
  end

  test 'imports Shopify customers who never bought, with tags, store and marketing consent' do
    data = shopify(111, email_marketing_consent: { 'state' => 'subscribed' },
                        default_address: { 'city' => 'Recife', 'province_code' => 'PE' })
    saved = @job.save_customers(@client, [data])

    customer = Customer.find_by!(shopify_customer_id: '111')
    assert_equal 1, saved
    assert_equal @client, customer.client
    assert_equal 'lead-lp, VIP', customer.tags
    assert_equal 'subscribed', customer.email_marketing_state
    assert_equal 'Recife', customer.default_address_city
  end

  test 'updates existing customers without touching purchase numbers or a missing consent' do
    existing = Customer.create!(shopify_customer_id: '222', first_name: 'Bia', orders_count: 4, total_spent: 500,
                                email_marketing_state: 'unsubscribed', default_address_city: 'Natal')

    @job.save_customers(@client, [shopify(222, first_name: 'Beatriz', tags: 'VIP')])

    existing.reload
    assert_equal 'Beatriz', existing.first_name
    assert_equal 'VIP', existing.tags
    assert_equal @client.id, existing.client_id
    assert_equal 4, existing.orders_count
    assert_equal 500, existing.total_spent
    assert_equal 'unsubscribed', existing.email_marketing_state
    assert_equal 'Natal', existing.default_address_city
  end

  test 'counts only customers that actually changed' do
    @job.save_customers(@client, [shopify(333)])

    assert_equal 0, @job.save_customers(@client, [shopify(333)])
  end

  test 'finishing a sync records the time and refreshes the profiles when something changed' do
    @job.stub(:sync_pages, [nil, 3]) do
      assert_enqueued_with(job: Customers::RefreshProfilesJob, args: [@client.id]) { @job.perform(@client.id) }
    end

    assert @client.reload.customers_synced_at.present?
  end

  test 'a long import continues in a new job and only finishes at the last page' do
    @job.stub(:sync_pages, ['next-page', 2]) { @job.perform(@client.id) }

    continuation = enqueued_jobs.sole
    assert_equal 'Customers::SyncJob', continuation['job_class']
    assert_equal [@client.id, 'next-page', true], continuation['arguments'].values_at(0, 1, 3)

    assert_nil @client.reload.customers_synced_at
    assert_no_enqueued_jobs(only: Customers::RefreshProfilesJob)
  end

  test 'nothing changed: no profile refresh' do
    @job.stub(:sync_pages, [nil, 0]) { @job.perform(@client.id) }

    assert_no_enqueued_jobs(only: Customers::RefreshProfilesJob)
  end

  test 'after the first import only asks Shopify for customers updated since the last sync' do
    assert_nil @job.send(:first_query, @client)[:updated_at_min]

    @client.update!(customers_synced_at: Time.zone.parse('2026-11-19 10:00'))
    assert_equal Time.zone.parse('2026-11-19 09:00').iso8601, @job.send(:first_query, @client)[:updated_at_min]
  end

  test 'without a store it schedules every active store with Shopify' do
    Client.create!(name: 'Sem Shopify', email: "s-#{SecureRandom.hex(4)}@example.com")

    @job.perform

    assert_enqueued_with(job: Customers::SyncJob, args: [@client.id])
    assert_equal Client.where(active: true).count(&:shopify_configured?), enqueued_jobs.size
  end
end
