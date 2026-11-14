require 'test_helper'

class Spreadsheets::CampaignRecipientsTest < ActiveSupport::TestCase
  setup do
    @client = Client.create!(name: 'Loja', email: "loja-#{SecureRandom.hex(4)}@example.com")
    @campaign = @client.campaigns.create!(name: 'Black Friday', status: 'sent')
  end

  def sheet_for(status)
    RubyXL::Parser.parse_buffer(Spreadsheets::CampaignRecipients.new(@campaign, status).to_xlsx)[0]
  end

  test 'sent list ends with the delivery date and keeps people without a profile' do
    @campaign.recipients.create!(email: 'ana@example.com', name: 'Ana', status: 'sent', sent_at: Time.zone.local(2026, 11, 14, 7, 40))
    @campaign.recipients.create!(email: 'bia@example.com', status: 'failed', error: 'caixa cheia')

    sheet = sheet_for('sent')

    assert_equal 'Enviado em', sheet[0].cells.last.value
    assert_equal 'ana@example.com', sheet[1][1].value
    assert_equal '14/11/2026 07:40', sheet[1].cells.last.value
    assert_nil sheet[2]
  end

  test 'failed list ends with the reason' do
    @campaign.recipients.create!(email: 'bia@example.com', status: 'failed', error: 'caixa cheia')

    sheet = sheet_for('failed')

    assert_equal 'Motivo', sheet[0].cells.last.value
    assert_equal 'caixa cheia', sheet[1].cells.last.value
  end

  test 'only the known statuses are exportable' do
    assert_equal %w[sent failed blocked], Spreadsheets::CampaignRecipients::STATUSES
  end

  test 'filename carries the campaign and the status' do
    assert_match(/\Acampanha_#{@campaign.id}_sent_\d{8}_\d{4}\.xlsx\z/, Spreadsheets::CampaignRecipients.new(@campaign, 'sent').filename)
  end
end
