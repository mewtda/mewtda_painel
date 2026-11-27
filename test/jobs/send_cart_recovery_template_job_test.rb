require 'test_helper'

class SendCartRecoveryTemplateJobTest < ActiveJob::TestCase
  class FakeApi
    attr_reader :calls

    def initialize(error: nil)
      @error = error
      @calls = []
    end

    def send_template(**args)
      raise @error if @error

      @calls << args
      'wamid.1'
    end
  end

  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             whatsapp_cloud_phone_number_id: '1', whatsapp_cloud_business_account_id: '2',
                             whatsapp_cloud_access_token: 't')
    @template = @client.whatsapp_templates.create!(
      label: 'Carrinho', name: 'carrinho_abandonado', body: 'Ei, {{1}}! Seu cupom está no link.', status: 'approved',
      button_text: 'Finalizar compra', button_url: 'https://www.mewtda.com.br/carrinho/{{1}}'
    )
    @automation = @client.automations.create!(
      name: 'Recuperação', kind: 'cart_recovery', whatsapp_template: @template, start_date: Date.current,
      no_end_date: true, send_delay_minutes: 60, include_coupon: true, coupon_code: 'FARAH'
    )
    customer = Customer.create!(first_name: 'Ana', name: 'Ana Souza', email: "#{SecureRandom.hex(4)}@example.com",
                                shopify_customer_id: SecureRandom.hex(6))
    @checkout = @client.abandoned_checkouts.create!(shopify_checkout_id: SecureRandom.hex(6), phone: '+5516992375432',
                                                    customer:, checkout_created_at: 2.hours.ago,
                                                    recovery_url: 'https://loja.com.br/123/checkouts/abc/recover?key=k')
  end

  def run_job(api = FakeApi.new)
    Whatsapp::Cloud::Api.stub(:new, ->(_client) { api }) { SendCartRecoveryTemplateJob.perform_now(@checkout.id) }
    api
  end

  test 'envia o modelo com o primeiro nome e o slug do checkout no botão' do
    api = run_job
    @checkout.reload

    assert_equal [{ to: '+5516992375432', name: 'carrinho_abandonado', language: 'pt_BR', body_params: ['Ana'],
                    url_button_param: @checkout.slug }], api.calls
    assert @checkout.first_notified_at
    assert_equal 'cloud', @checkout.whatsapp_provider
    assert_equal 'wamid.1', @checkout.whatsapp_message_id
    assert_equal 'sent', @checkout.whatsapp_status
    assert_equal 'FARAH', @checkout.first_coupon_code
    assert_equal 'Ei, Ana! Seu cupom está no link.', @checkout.first_message_sent
    assert_nil @checkout.skip_reason
  end

  test 'sem cliente vinculado usa o nome guardado no checkout' do
    @checkout.update!(customer: nil, customer_name: 'daniel fernandes')
    api = run_job

    assert_equal ['Daniel'], api.calls.first[:body_params]
  end

  test 'não envia de novo um checkout já notificado' do
    @checkout.update!(first_notified_at: 1.hour.ago)

    assert_empty run_job.calls
  end

  test 'modelo não aprovado não envia e mantém pendente' do
    @template.update!(status: 'paused')

    assert_empty run_job.calls
    assert_nil @checkout.reload.first_notified_at
  end

  test 'Meta fora do ar mantém o checkout pendente' do
    run_job(FakeApi.new(error: Whatsapp::Cloud::Api::Error.new('Sem resposta da Meta')))

    assert_nil @checkout.reload.first_notified_at
  end

  test 'número bloqueado marca como enviado com o motivo' do
    run_job(FakeApi.new(error: Whatsapp::Cloud::Api::Blocked.new('Usuário bloqueou', code: 131_050)))
    @checkout.reload

    assert @checkout.first_notified_at
    assert_match 'Usuário bloqueou', @checkout.skip_reason
  end
end
