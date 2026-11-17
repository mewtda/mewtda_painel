module Insights
  # Gera o insight semanal de conversão de um cliente: resume os últimos 7 dias
  # do pixel (funil por sessão, abandono, pedidos, produtos, origem e
  # dispositivos) e pede ao Claude uma leitura curta, em português, com uma
  # ação concreta. Fica salvo em conversion_insights (um por semana).
  class WeeklyConversion
    MODEL = 'claude-opus-5-5'.freeze
    MAX_TOKENS = 4000

    SYSTEM_PROMPT = <<~PROMPT.freeze
      Você é analista de conversão de e-commerce e escreve para o dono de uma loja Shopify brasileira.
      Você recebe, em JSON, os números dos últimos 7 dias do pixel da loja comparados com os 7 dias anteriores:
      o funil por sessão (cada etapa conta sessões únicas), abandono de carrinho, pedidos e receita da Shopify,
      produtos mais vistos e mais adicionados ao carrinho, origem do tráfego e dispositivos.

      Escreva UM insight, em português do Brasil, com no máximo 3 frases curtas:
      1. o ponto mais importante da semana, citando os números que o sustentam;
      2. a causa provável, ligando dois dados que se complementam (por exemplo, a etapa com a maior perda e o
         dispositivo ou produto que explica essa perda);
      3. uma ação concreta e específica para a próxima semana.

      Use só os números recebidos; não invente dados nem metas. Se a amostra for pequena demais para concluir
      algo (menos de 100 sessões), diga isso em uma frase e sugira o que acompanhar. Responda só com o texto do
      insight, sem título, listas ou markdown.
    PROMPT

    def initialize(client, client_api: nil, today: Time.zone.today)
      @client = client
      @api = client_api
      @week_start = today.beginning_of_week
    end

    def call
      existing = ConversionInsight.find_by(client: @client, week_start: @week_start)
      return existing if existing

      metrics = self.class.metrics_for(@client)
      return if metrics.nil?

      body = ask_claude(metrics)
      return if body.blank?

      ConversionInsight.create!(client: @client, week_start: @week_start, body: body, metrics: metrics, model: MODEL)
    rescue ActiveRecord::RecordNotUnique
      ConversionInsight.find_by(client: @client, week_start: @week_start)
    end

    # Números da semana, no mesmo cálculo da tela Trackeamento site.
    def self.metrics_for(client)
      report = Tracking::DashboardReport.new(client: client, period: '7').assigns
      return if report[:empty_state] || report[:unique_sessions].to_i.zero?

      {
        loja: client.name,
        periodo: 'últimos 7 dias',
        sessoes: report[:unique_sessions],
        sessoes_semana_anterior: report[:prev_unique_sessions],
        funil: report[:funnel].map do |step|
          step.slice(:label, :count, :prev_count, :pct_total, :pct_step, :lost)
        end,
        taxa_conversao_pct: report[:conversion_rate],
        taxa_conversao_semana_anterior_pct: report[:prev_conversion_rate],
        abandono_carrinho: { sessoes: report[:abandoned_carts], pct: report[:abandoned_rate] },
        pedidos_shopify: report[:orders_summary].transform_values { |v| v.is_a?(BigDecimal) ? v.to_f : v },
        produtos_mais_vistos: Array(report[:top_products_viewed]).first(5),
        produtos_mais_adicionados_ao_carrinho: Array(report[:top_products_carted]).first(5),
        origem_trafego_sessoes: report[:referrers],
        dispositivos_sessoes: report[:devices]
      }.as_json
    end

    private

    def ask_claude(metrics)
      message = api.beta.messages.create(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        output_config: { effort: :low },
        betas: ['server-side-fallback-2026-07-01'],
        fallbacks: :default,
        system_: SYSTEM_PROMPT,
        messages: [{ role: 'user', content: metrics.to_json }]
      )
      return if message.stop_reason == :refusal

      message.content.select { |block| block.type == :text }.map(&:text).join("\n").strip
    end

    def api
      @api ||= Anthropic::Client.new
    end
  end
end
