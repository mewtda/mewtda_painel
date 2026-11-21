module Whatsapp
  module Cloud
    # Sincroniza os modelos do cliente com a conta do WhatsApp conectada na Meta (casando pelo nome).
    # Os modelos são criados no Gerenciador do WhatsApp; o painel só importa:
    # - importa os modelos novos (texto, rodapé, botão, idioma e status);
    # - atualiza status e motivo de rejeição dos que já estão no painel, e desativa os excluídos na Meta;
    # - puxa os números da Meta por modelo (enviadas, entregues, lidas, cliques) dos últimos STATS_DAYS dias.
    # Modelo que o painel não consegue enviar (cabeçalho com mídia, variáveis além do nome, botão com
    # variável, autenticação) é importado com unsupported_reason e não aparece na escolha da campanha.
    class TemplateSync
      STATS_DAYS = 90
      Result = Struct.new(:imported, :stats_error, keyword_init: true)

      def initialize(client, stats: true)
        @client = client
        @stats = stats
      end

      def call
        remote = api.templates
        imported = 0
        by_name = @client.whatsapp_templates.index_by(&:name)
        remote.each do |data|
          template = by_name[data['name']]
          if template.nil?
            import(data)
            imported += 1
          elsif template.status != 'draft'
            update_status(template, data)
          end
        end
        disable_missing(remote.map { |data| data['name'] })
        Result.new(imported:, stats_error: (refresh_stats if @stats))
      end

      private

      def api = @api ||= Api.new(@client)

      def update_status(template, data)
        status = normalized_status(data, template.status)
        template.update_columns(
          status:, meta_id: data['id'].presence || template.meta_id,
          rejection_reason: status == 'rejected' ? data['rejected_reason'].presence : nil,
          synced_at: Time.current, updated_at: Time.current
        )
      end

      def import(data)
        parsed = TemplateComponents.new(data).to_h
        template = @client.whatsapp_templates.new(
          name: data['name'], label: data['name'].to_s.tr('_', ' ').capitalize.first(120),
          category: data['category'].presence || 'MARKETING', language: data['language'].presence || 'pt_BR',
          meta_id: data['id'], status: normalized_status(data, 'pending'),
          rejection_reason: (data['rejected_reason'] if data['rejected_reason'].present? && data['rejected_reason'] != 'NONE'),
          imported: true, synced_at: Time.current, **parsed
        )
        # O texto vem pronto da Meta: as regras de escrita do painel (só {{1}}, exemplo obrigatório) não valem aqui.
        template.save!(validate: false)
      rescue ActiveRecord::RecordNotUnique
        nil
      end

      # Modelo que não existe mais na conta (excluído no Gerenciador do WhatsApp) não pode ser enviado.
      def disable_missing(remote_names)
        @client.whatsapp_templates.where.not(status: %w[draft disabled]).where.not(name: remote_names)
               .update_all(status: 'disabled', rejection_reason: 'Excluído na Meta', synced_at: Time.current,
                           updated_at: Time.current)
      end

      def normalized_status(data, fallback)
        status = data['status'].to_s.downcase
        WhatsappTemplate::STATUSES.include?(status) ? status : fallback
      end

      # Devolve a mensagem de erro da Meta (por exemplo, insights desligados) ou nil.
      def refresh_stats
        templates = @client.whatsapp_templates.where.not(meta_id: [nil, ''])
        return if templates.none?

        now = Time.current
        # A Meta recusa início fora da janela de 90 dias; começar no início do dia, 89 dias atrás, fica dentro.
        from = (now - (STATS_DAYS - 1).days).beginning_of_day
        totals = api.template_analytics(templates.pluck(:meta_id), from:, to: now)
        templates.find_each do |template|
          row = totals.fetch(template.meta_id.to_s, { sent: 0, delivered: 0, read: 0, clicked: 0 })
          template.update_columns(stats_sent: row[:sent], stats_delivered: row[:delivered], stats_read: row[:read],
                                  stats_clicked: row[:clicked], stats_synced_at: now)
        end
        nil
      rescue Api::Error => e
        e.message
      end
    end
  end
end
