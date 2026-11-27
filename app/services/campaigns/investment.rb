module Campaigns
  # Investimento das campanhas: o que já foi gasto (mensagens enviadas) e a previsão do que ainda vai sair
  # (mensagens agendadas, enviando ou pausadas). Painel = e-mail a R$ 4/mil + R$ 0,10 por WhatsApp, na fatura;
  # Meta = estimativa por WhatsApp de marketing, paga direto no cartão da conta do WhatsApp da loja.
  class Investment
    Cost = Struct.new(:emails, :whatsapps) do
      def self.zero = new(0, 0)

      def panel
        (emails * Billing::Invoice::EMAIL_PRICE_PER_THOUSAND / 1000) +
          (whatsapps * Billing::Invoice::WHATSAPP_PRICE_PER_MESSAGE)
      end

      def meta = whatsapps * Campaigns::Performance::META_MARKETING_PRICE
      def total = panel + meta
      def zero? = emails.zero? && whatsapps.zero?
      def +(other) = Cost.new(emails + other.emails, whatsapps + other.whatsapps)
    end

    Row = Struct.new(:spent, :forecast)

    def initialize(client, campaigns)
      @client = client
      @campaigns = campaigns.to_a
      @rows = {}
    end

    def for(campaign)
      @rows[campaign.id] ||= Row.new(spent(campaign), forecast(campaign))
    end

    def spent_total = sum(:spent)
    def forecast_total = sum(:forecast)

    private

    attr_reader :client, :campaigns

    def sum(kind) = campaigns.map { |campaign| self.for(campaign).public_send(kind) }.reduce(Cost.zero, :+)

    def spent(campaign)
      count_by_channel(campaign.messages) { |message| message.sent_count.to_i }
    end

    # Só o que falta: mensagem com público já congelado conta quem ainda não foi processado; a que ainda não
    # começou conta o público de hoje do canal (pode mudar até o envio).
    def forecast(campaign)
      count_by_channel(campaign.messages.select(&:runnable?)) do |message|
        message.recipients_count ? remaining(message) : audience(campaign, message.channel)
      end
    end

    def remaining(message)
      done = message.sent_count.to_i + message.failed_count.to_i + message.blocked_count.to_i
      [message.recipients_count - done, 0].max
    end

    def count_by_channel(messages)
      messages.each_with_object(Cost.zero) do |message, cost|
        count = yield(message)
        message.whatsapp? ? cost.whatsapps += count : cost.emails += count
      end
    end

    def audience(campaign, channel)
      @audiences ||= {}
      @audiences[[campaign.id, channel]] ||=
        Campaigns::Audience.new(client, campaign.segments.to_a, channel:).call.recipients
    end
  end
end
