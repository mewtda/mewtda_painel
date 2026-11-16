module CustomAutomations
  # Automações feitas sob medida pra um cliente. Cada entrada diz pra quais
  # clientes ela aparece — o match é pelo nome normalizado (sem acento, espaço
  # ou hífen), então "Fernanda Farah", "fernanda-farah" e "FernandaFarah" batem.
  module Registry
    AUTOMATIONS = {
      'fernanda_farah_transfer_note' => {
        title: 'Nota de transferência mensal (matriz → e-commerce)',
        description: 'Lê os pedidos do período na Shopify, monta uma NF de transferência (CFOP 5152) no Tiny da ' \
                     'matriz em nome da filial do e-commerce, gera a planilha de conferência e só emite depois ' \
                     'da aprovação.',
        icon: 'fa-solid fa-file-invoice',
        client_keys: %w[fernandafarah]
      }
    }.freeze

    # Rotinas sob medida que rodam sozinhas (sem tela): cada uma é um service
    # com `new(client, **options).call`, ligada aos clientes de client_keys.
    # O CustomAutomations::RoutineJob roda todas (ou uma, pelo kind) para cada
    # cliente ativo com Shopify configurada — pra criar outra, basta o service
    # e uma entrada aqui; o agendamento do Sidekiq não muda.
    ROUTINES = {
      'oneway_address_number_fix' => {
        title: 'Número do endereço no lugar certo',
        description: 'Move o número da casa do complemento para a rua nos pedidos ainda não enviados ' \
                     '("Rua Pio IV" / "210" → "Rua Pio IV, 210").',
        service: 'CustomAutomations::OnewayAddressNumberFix',
        options: { lookback_hours: 72 },
        client_keys: %w[oneway]
      }
    }.freeze

    module_function

    def routine(kind)
      ROUTINES[kind.to_s]
    end

    def routines_for(client)
      return {} if client.nil?

      key = normalize(client.name)
      ROUTINES.select { |_kind, config| config[:client_keys].include?(key) }
    end

    def kinds
      AUTOMATIONS.keys
    end

    def find(kind)
      AUTOMATIONS[kind.to_s]
    end

    def for_client(client)
      return {} if client.nil?

      key = normalize(client.name)
      AUTOMATIONS.select { |_kind, config| config[:client_keys].include?(key) }
    end

    def available?(client, kind)
      for_client(client).key?(kind.to_s)
    end

    def normalize(name)
      name.to_s.parameterize.delete('-')
    end
  end
end
