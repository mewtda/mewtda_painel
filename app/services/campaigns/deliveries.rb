module Campaigns
  # Quem do público recebeu cada mensagem da campanha. As linhas são as pessoas dos segmentos da campanha
  # (mais quem recebeu e depois saiu do segmento); as colunas, as mensagens já confirmadas. Cada célula diz
  # se a mensagem foi enviada, falhou, foi bloqueada, está na fila ou, se a pessoa não está na lista de
  # envio daquela mensagem, por quê (sem celular, sem e-mail, lista de recusa, entrou depois do envio).
  class Deliveries
    FILTERS = { 'todos' => 'Todo o público', 'receberam' => 'Receberam alguma mensagem',
                'nao_receberam' => 'Não receberam nenhuma' }.freeze

    Cell = Struct.new(:status, :at, :detail, keyword_init: true) do
      def label = LABELS.fetch(status)
      def tone = TONES.fetch(status)
    end
    LABELS = { 'sent' => 'Enviada', 'failed' => 'Falhou', 'blocked' => 'Bloqueada', 'pending' => 'Na fila',
               'missing' => 'Não recebeu' }.freeze
    TONES = { 'sent' => 'success', 'failed' => 'danger', 'blocked' => 'warning', 'pending' => 'info',
              'missing' => 'neutral' }.freeze

    attr_reader :campaign

    def initialize(campaign)
      @campaign = campaign
    end

    def messages
      @messages ||= campaign.messages.where.not(status: 'draft').includes(:email_template, :whatsapp_template)
                            .order(:position, :id).to_a
    end

    # Perfis do público, já filtrados; ordene e pagine por fora.
    def profiles(filter: 'todos', query: nil)
      scope = CustomerProfile.where(client_id: campaign.client_id)
                             .where("customer_profiles.id IN (#{segment_profiles.reselect('customer_profiles.id').to_sql}) " \
                                    "OR customer_profiles.customer_id IN (#{recipient_customer_ids_sql})")
      scope = scope.where(received_sql) if filter == 'receberam'
      scope = scope.where.not(received_sql) if filter == 'nao_receberam'
      search(scope, query)
    end

    # { profile_id => [Cell por mensagem, na ordem de #messages] }
    def cells_for(profiles)
      profiles = profiles.to_a
      recipients = recipients_for(profiles)
      suppressed = suppressed_emails(profiles)
      profiles.to_h do |profile|
        [profile.id, messages.map { |message| cell(message, profile, recipients, suppressed) }]
      end
    end

    private

    def segment_profiles
      # Consulta nova: a associação da campanha pode estar carregada (e velha) no objeto.
      segments = Segment.where(id: CampaignSegment.where(campaign_id: campaign.id).select(:segment_id)).to_a
      Audience.new(campaign.client, segments).segment_profiles
    end

    def recipient_customer_ids_sql
      CampaignRecipient.where(campaign_id: campaign.id).where.not(customer_id: nil).select(:customer_id).to_sql
    end

    # Recebeu alguma mensagem: enviada para o cadastro (ou um cadastro mesclado) ou para o e-mail dele.
    def received_sql
      Arel.sql(<<~SQL.squish)
        EXISTS (SELECT 1 FROM campaign_recipients r WHERE r.campaign_id = #{campaign.id.to_i} AND r.status = 'sent'
          AND (r.customer_id = customer_profiles.customer_id OR r.customer_id = ANY(customer_profiles.merged_customer_ids)
               OR (r.channel = 'email' AND r.email = LOWER(customer_profiles.email))))
      SQL
    end

    def search(scope, query)
      query = query.to_s.strip
      return scope if query.blank?

      like = "%#{CustomerProfile.sanitize_sql_like(query)}%"
      digits = query.gsub(/\D/, '')
      conditions = ['customer_profiles.name ILIKE :like', 'customer_profiles.email ILIKE :like']
      conditions << "regexp_replace(customer_profiles.phone, '\\D', '', 'g') LIKE :digits" if digits.length >= 4
      scope.where(conditions.join(' OR '), like:, digits: "%#{digits}%")
    end

    # Destinatários da campanha ligados às pessoas da página, por cadastro e por endereço
    # (o WhatsApp não repete número: dois cadastros com o mesmo celular recebem uma vez só).
    def recipients_for(profiles)
      ids = profiles.flat_map(&:customer_ids).compact
      emails = profiles.filter_map { |p| p.email.to_s.strip.downcase.presence }
      phones = profiles.filter_map { |p| Whatsapp::Phone.normalize(p.phone) }
      rows = CampaignRecipient.where(campaign_id: campaign.id)
                              .where('customer_id IN (:ids) OR email IN (:emails) OR phone IN (:phones)',
                                     ids: ids.presence || [0], emails: emails.presence || [''], phones: phones.presence || [''])
      rows.each_with_object(Hash.new { |h, k| h[k] = {} }) do |recipient, index|
        by_message = index[recipient.campaign_message_id]
        by_message[[:customer, recipient.customer_id]] = recipient if recipient.customer_id
        by_message[[:address, recipient.channel == 'whatsapp' ? recipient.phone : recipient.email]] = recipient
      end
    end

    def suppressed_emails(profiles)
      emails = profiles.filter_map { |p| p.email.presence }
      EmailSuppression.where(client_id: campaign.client_id, email: emails).pluck(:email).to_set
    end

    def cell(message, profile, recipients, suppressed)
      address = address_for(message, profile)
      found = recipients[message.id]
      recipient = profile.customer_ids.lazy.filter_map { |id| found[[:customer, id]] }.first
      recipient ||= found[[:address, address]] if address
      return recipient_cell(recipient, other_profile: recipient.customer_id && !profile.customer_ids.include?(recipient.customer_id)) if recipient

      Cell.new(status: 'missing', detail: missing_reason(message, profile, address, suppressed))
    end

    def recipient_cell(recipient, other_profile:)
      detail = recipient.error.presence if recipient.status == 'failed'
      detail = 'Mesmo número ou e-mail de outro cadastro' if other_profile && detail.nil?
      Cell.new(status: recipient.status, at: recipient.sent_at, detail:)
    end

    def address_for(message, profile)
      message.whatsapp? ? Whatsapp::Phone.normalize(profile.phone) : profile.email.to_s.strip.downcase.presence
    end

    def missing_reason(message, profile, address, suppressed)
      return 'A mensagem ainda não começou a sair' unless message.audience_frozen_at
      return(message.whatsapp? ? 'Sem celular válido no cadastro' : 'Sem e-mail no cadastro') unless address
      return 'Está na lista de recusa de e-mail' if message.email? && suppressed.include?(profile.email)
      return 'Entrou no segmento depois; recebe na próxima rodada' if message.continuing?

      'Não estava no segmento quando a mensagem saiu'
    end
  end
end
