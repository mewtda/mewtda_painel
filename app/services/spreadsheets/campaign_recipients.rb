module Spreadsheets
  class CampaignRecipients < Base
    STATUSES = %w[sent failed blocked].freeze

    def initialize(campaign, status)
      super()
      @campaign = campaign
      @status = status
    end

    def filename = "campanha_#{campaign.id}_#{status}_#{stamp}.xlsx"

    private

    attr_reader :campaign, :status

    def sheet_name = 'Destinatários'
    def headers = Customers::HEADERS + [status == 'failed' ? 'Motivo' : 'Enviado em']

    def rows
      recipients = campaign.recipients.where(status:).order(:id).to_a
      profiles = campaign.client.customer_profiles.where(customer_id: recipients.filter_map(&:customer_id)).index_by(&:customer_id)
      recipients.map { |recipient| person(recipient, profiles[recipient.customer_id]) + [detail(recipient)] }
    end

    def person(recipient, profile)
      return Customers.row(profile) if profile

      [recipient.name, recipient.email] + Array.new(Customers::HEADERS.size - 2)
    end

    def detail(recipient)
      status == 'failed' ? recipient.error : recipient.sent_at&.strftime('%d/%m/%Y %H:%M')
    end
  end
end
