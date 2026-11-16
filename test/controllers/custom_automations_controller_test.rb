require 'test_helper'

class CustomAutomationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def sign_in_client_user(client_name)
    Profile.find_or_create_by!(id: Profile::USER) { |p| p.name = 'User' }
    client = Client.create!(name: client_name, email: "c-#{SecureRandom.hex(4)}@example.com")
    user = User.create!(name: 'User', email: "user-#{SecureRandom.hex(4)}@example.com",
                        password: 'password123', password_confirmation: 'password123',
                        profile_id: Profile::USER, client: client)
    sign_in user
    client
  end

  def create_run(client, **attrs)
    CustomAutomationRun.create!({ client: client, kind: 'fernanda_farah_transfer_note',
                                  period_start: Date.new(2026, 8, 1), period_end: Date.new(2026, 8, 31),
                                  order_filter: 'paid', price_percentage: 70 }.merge(attrs))
  end

  test 'lists the transfer note automation only for Fernanda Farah' do
    sign_in_client_user('Fernanda Farah')
    get custom_automations_path

    assert_response :success
    assert_includes response.body, 'Nota de transferência mensal'
  end

  test 'shows the empty state for other clients and blocks creating runs' do
    sign_in_client_user('Outra Loja')
    get custom_automations_path
    assert_includes response.body, 'Nenhuma automação personalizada'

    assert_no_difference -> { CustomAutomationRun.count } do
      post custom_automations_path, params: { custom_automation_run: {
        kind: 'fernanda_farah_transfer_note', period_start: '2026-08-01', period_end: '2026-08-31',
        order_filter: 'paid', price_percentage: 70
      } }
    end
  end

  test 'shows the routines registered for the client and runs one on demand' do
    client = sign_in_client_user('OneWay')
    get custom_automations_path

    assert_response :success
    assert_includes response.body, 'Correção de endereço de entrega'
    assert_not_includes response.body, 'Nenhuma automação personalizada'
    assert_not_includes response.body, 'Nota de transferência mensal'

    assert_enqueued_with(job: CustomAutomations::RoutineJob, args: ['oneway_address_number_fix', client.id]) do
      post run_routine_custom_automations_path(kind: 'oneway_address_number_fix')
    end
    assert_redirected_to custom_automations_path
  end

  test 'does not run a routine for a client it is not registered for' do
    sign_in_client_user('Fernanda Farah')

    assert_no_enqueued_jobs only: CustomAutomations::RoutineJob do
      post run_routine_custom_automations_path(kind: 'oneway_address_number_fix')
    end
    assert_redirected_to custom_automations_path
  end

  test 'creating a run enqueues the build job' do
    sign_in_client_user('Fernanda Farah')

    assert_enqueued_with(job: CustomAutomationBuildJob) do
      post custom_automations_path, params: { custom_automation_run: {
        kind: 'fernanda_farah_transfer_note', period_start: '2026-08-01', period_end: '2026-08-31',
        order_filter: 'not_cancelled', price_percentage: 70
      } }
    end

    run = CustomAutomationRun.last
    assert_equal 'not_cancelled', run.order_filter
    assert_redirected_to custom_automation_path(run)
  end

  test 'emit only works once while awaiting review' do
    client = sign_in_client_user('Fernanda Farah')
    run = create_run(client, status: 'awaiting_review', tiny_note_id: '987')

    assert_enqueued_jobs 1, only: CustomAutomationEmitJob do
      post emit_custom_automation_path(run)
      post emit_custom_automation_path(run)
    end
    assert_equal 'emitting', run.reload.status
  end

  test 'downloads the conference spreadsheet' do
    client = sign_in_client_user('Fernanda Farah')
    run = create_run(client, status: 'awaiting_review', total_value: 10,
                             items: [{ 'sku' => 'A', 'description' => 'Vestido', 'quantity' => 1,
                                       'average_price' => 14.29, 'unit_value' => 10.0, 'total' => 10.0,
                                       'tiny_found' => true }])

    get spreadsheet_custom_automation_path(run)

    assert_response :success
    assert_equal 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', response.media_type
    sheet = RubyXL::Parser.parse_buffer(response.body)
    assert_equal 'A', sheet['Itens'][1][0].value
  end

  test 'cannot see runs from another client' do
    other = Client.create!(name: 'Fernanda Farah', email: "x-#{SecureRandom.hex(4)}@example.com")
    run = create_run(other)
    sign_in_client_user('Fernanda Farah')

    get custom_automation_path(run)
    assert_response :not_found
  end
end
