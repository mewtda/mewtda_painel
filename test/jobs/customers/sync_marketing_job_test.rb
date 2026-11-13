require 'test_helper'

class SyncMarketingJobTest < ActiveJob::TestCase
  setup do
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             shopify_shop_url: 'loja.myshopify.com', shopify_access_token: 'token')
    @ana = Customer.create!(first_name: 'Ana', shopify_customer_id: '111', email_marketing_state: 'subscribed')
    @bia = Customer.create!(first_name: 'Bia', shopify_customer_id: '222')
  end

  def run_job(changed)
    job = Customers::SyncMarketingJob.new
    job.stub(:fetch_changed, changed) { job.perform(@client.id) }
  end

  test 'updates the marketing state of customers that changed in Shopify' do
    run_job([
      { 'id' => 111, 'email_marketing_consent' => { 'state' => 'unsubscribed' } },
      { 'id' => 222, 'email_marketing_consent' => { 'state' => 'subscribed' } }
    ])

    assert_equal 'unsubscribed', @ana.reload.email_marketing_state
    assert_equal 'subscribed', @bia.reload.email_marketing_state
  end

  test 'ignores Shopify customers we do not have and unchanged states' do
    run_job([
      { 'id' => 999, 'email_marketing_consent' => { 'state' => 'subscribed' } },
      { 'id' => 111, 'email_marketing_consent' => { 'state' => 'subscribed' } }
    ])

    assert_equal 'subscribed', @ana.reload.email_marketing_state
    assert_no_enqueued_jobs(only: Customers::RefreshProfilesJob)
  end

  test 'refreshes the profiles only when something changed' do
    assert_enqueued_with(job: Customers::RefreshProfilesJob, args: [@client.id]) do
      run_job([{ 'id' => 222, 'email_marketing_consent' => { 'state' => 'pending' } }])
    end
  end
end
