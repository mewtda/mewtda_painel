require 'test_helper'

class ProcessCartRecoveryAutomationsJobTest < ActiveJob::TestCase
  def setup
    @client = Client.create!(name: 'Loja Teste', email: "loja-#{SecureRandom.hex(4)}@example.com",
                             whatsapp_cloud_phone_number_id: '111', whatsapp_cloud_business_account_id: '222',
                             whatsapp_cloud_access_token: 'token')
    @template = @client.whatsapp_templates.create!(label: 'Carrinho', body: 'Ei, {{1}}!', status: 'approved')
  end

  def create_automation(attrs = {})
    @client.automations.create!({
      name: 'Recuperação', kind: 'cart_recovery', whatsapp_template: @template,
      start_date: Date.current - 1.day, end_date: Date.current + 1.year,
      send_delay_minutes: 60
    }.merge(attrs))
  end

  def create_checkout(attrs = {})
    @client.abandoned_checkouts.create!({
      shopify_checkout_id: SecureRandom.hex(6), phone: '+5511999999999',
      checkout_created_at: Time.current
    }.merge(attrs))
  end

  test 'envia o modelo depois do tempo configurado para um checkout pendente' do
    create_automation
    checkout = create_checkout(checkout_created_at: 2.hours.ago)

    assert_enqueued_with(job: SendCartRecoveryTemplateJob, args: [checkout.id]) do
      ProcessCartRecoveryAutomationsJob.perform_now(@client.id)
    end
  end

  test 'checkouts com mais de 24 horas nunca recebem a mensagem' do
    create_automation
    create_checkout(checkout_created_at: 25.hours.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryTemplateJob) do
      ProcessCartRecoveryAutomationsJob.perform_now(@client.id)
    end
  end

  test 'modo teste só envia para o número de teste' do
    create_automation(test_phone: '11 98888-7777')
    create_checkout(checkout_created_at: 2.hours.ago)
    mine = create_checkout(checkout_created_at: 2.hours.ago, phone: '+55 11 98888-7777')

    assert_enqueued_jobs 1, only: SendCartRecoveryTemplateJob do
      ProcessCartRecoveryAutomationsJob.perform_now(@client.id)
    end
    assert_enqueued_with(job: SendCartRecoveryTemplateJob, args: [mine.id])
  end

  test 'checkouts de antes da data de início da automação não recebem a mensagem' do
    create_automation(start_date: Date.current)
    create_checkout(checkout_created_at: Date.current.beginning_of_day - 1.minute)
    today = create_checkout(checkout_created_at: Date.current.beginning_of_day + 1.minute)

    travel_to(Date.current.beginning_of_day + 2.hours) do
      assert_enqueued_jobs 1, only: SendCartRecoveryTemplateJob do
        ProcessCartRecoveryAutomationsJob.perform_now(@client.id)
      end
    end
    assert_enqueued_with(job: SendCartRecoveryTemplateJob, args: [today.id])
  end

  test 'não envia antes do tempo configurado' do
    create_automation(send_delay_minutes: 120)
    create_checkout(checkout_created_at: 10.minutes.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryTemplateJob) do
      ProcessCartRecoveryAutomationsJob.perform_now(@client.id)
    end
  end

  test 'checkout que já recebeu a mensagem não recebe de novo' do
    create_automation
    create_checkout(checkout_created_at: 2.hours.ago, first_notified_at: 1.hour.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryTemplateJob) do
      ProcessCartRecoveryAutomationsJob.perform_now(@client.id)
    end
  end

  test 'loja sem API Oficial configurada não envia' do
    create_automation
    @client.update!(whatsapp_cloud_access_token: nil)
    create_checkout(checkout_created_at: 2.hours.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryTemplateJob) do
      ProcessCartRecoveryAutomationsJob.perform_now(@client.id)
    end
  end

  test 'automação desligada sem modelo não envia' do
    create_automation(whatsapp_template: nil, active: false)
    create_checkout(checkout_created_at: 2.hours.ago)

    assert_no_enqueued_jobs(only: SendCartRecoveryTemplateJob) do
      ProcessCartRecoveryAutomationsJob.perform_now(@client.id)
    end
  end

  test 'sem data final continua rodando' do
    create_automation(end_date: nil)
    checkout = create_checkout(checkout_created_at: 2.hours.ago)

    assert_enqueued_with(job: SendCartRecoveryTemplateJob, args: [checkout.id]) do
      ProcessCartRecoveryAutomationsJob.perform_now(@client.id)
    end
  end

  test 'schedule.yml sincroniza os checkouts e processa a recuperação de carrinho' do
    schedule = YAML.load_file(Rails.root.join('config/schedule.yml'))
    classes = schedule.values.map { |job| job['class'] }
    assert_includes classes, 'DailyAbandonedCheckoutsSyncJob'
    assert_includes classes, 'ProcessCartRecoveryAutomationsJob'
    refute_includes classes, 'Whatsapp::RecoveryJob'
  end
end
