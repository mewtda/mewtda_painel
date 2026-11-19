module Spreadsheets
  class CampaignRecipients < Base
    STATUSES = %w[sent failed blocked].freeze

    def initialize(campaign, status, message: nil)
      super()
      @campaign = campaign
      @status = status
      @message = message
    end

    def filename = "campanha_#{campaign.id}#{"_mensagem_#{message.id}" if message}_#{status}_#{stamp}.xlsx"

    private

    attr_reader :campaign, :status, :message

    PHONE = Customers::HEADERS.index('Telefone')

    def sheet_name = 'Destinatários'
    def headers = Customers::HEADERS + ['Canal', status == 'failed' ? 'Motivo' : 'Enviado em']

    def rows
      scope = message ? message.recipients : campaign.recipients
      recipients = scope.where(status:).order(:id).to_a
      profiles = campaign.client.customer_profiles.where(customer_id: recipients.filter_map(&:customer_id)).index_by(&:customer_id)
      recipients.map do |recipient|
        person(recipient, profiles[recipient.customer_id]) +
          [CampaignMessage::CHANNEL_LABELS.fetch(recipient.channel, recipient.channel), detail(recipient)]
      end
    end

    # Dados do perfil; o telefone/e-mail usado no envio prevalece sobre o do cadastro.
    def person(recipient, profile)
      row = profile ? Customers.row(profile) : [recipient.name, recipient.email] + Array.new(Customers::HEADERS.size - 2)
      row[PHONE] = recipient.phone if recipient.phone.present?
      row
    end

    def detail(recipient)
      status == 'failed' ? recipient.error : recipient.sent_at&.strftime('%d/%m/%Y %H:%M')
    end
  end
end
