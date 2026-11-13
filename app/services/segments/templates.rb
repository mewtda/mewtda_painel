module Segments
  # Segmentos sugeridos (galeria de "Criar segmento").
  module Templates
    def self.cond(field, op, value = nil, value2 = nil)
      { 'field' => field, 'op' => op, 'value' => value, 'value2' => value2 }.compact
    end

    def self.rules(*conditions) = { 'groups' => [{ 'conditions' => conditions }] }

    def self.all
      last_year = Time.zone.today.year - 1
      {
        'todos' => { name: 'Todos os clientes', popular: false, icon: 'fa-users',
                     description: 'Todos os clientes da base com ao menos uma compra.',
                     rules: rules(cond('orders_count', 'gte', '1')) },
        'uma_compra' => { name: 'Compraram apenas uma vez', popular: true, icon: 'fa-1',
                          description: 'Ideal para incentivar a segunda compra.',
                          rules: rules(cond('orders_count', 'eq', '1')) },
        'duas_compras' => { name: 'Compraram duas vezes', popular: false, icon: 'fa-2',
                            description: 'No meio do caminho para virar cliente fiel.',
                            rules: rules(cond('orders_count', 'eq', '2')) },
        'tres_mais' => { name: 'Compraram três vezes ou mais', popular: false, icon: 'fa-gem',
                         description: 'Alto potencial de fidelidade. Merecem benefícios VIP.',
                         rules: rules(cond('orders_count', 'gte', '3')) },
        'ativos' => { name: 'Clientes ativos', popular: true, icon: 'fa-bolt',
                      description: 'Lado direito da Matriz RFM: compraram recentemente.',
                      rules: rules(cond('rfm_segment', 'in', CustomerProfile::ACTIVE_SEGMENTS)) },
        'inativos' => { name: 'Clientes inativos', popular: true, icon: 'fa-moon',
                        description: 'Lado esquerdo da Matriz RFM: esfriando ou sumidos. Hora de reconquistar.',
                        rules: rules(cond('rfm_segment', 'in', CustomerProfile::INACTIVE_SEGMENTS)) },
        'campeoes' => { name: 'Clientes campeões', popular: true, icon: 'fa-trophy',
                        description: 'Compram muito, com frequência e recentemente.',
                        rules: rules(cond('rfm_segment', 'in', ['champion'])) },
        'reconquista' => { name: 'Não pode perder + Em risco', popular: false, icon: 'fa-life-ring',
                           description: 'Eram bons clientes e pararam de comprar. Prioridade de reconquista.',
                           rules: rules(cond('rfm_segment', 'in', %w[cant_lose at_risk])) },
        'sem_compra_90' => { name: 'Sem comprar há 90 dias', popular: false, icon: 'fa-hourglass-half',
                             description: 'Já compraram, mas não voltam há mais de 3 meses.',
                             rules: rules(cond('last_order_at', 'more_than_days', '90')) },
        'black_friday' => { name: "Compraram na Black Friday #{last_year}", popular: false, icon: 'fa-tags',
                            description: 'Público que responde a promoções. Prioridade para a próxima Black Friday.',
                            rules: rules(cond('purchase_date', 'between', "#{last_year}-11-20", "#{last_year}-12-02")) },
        'cupom' => { name: 'Compram com cupom', popular: false, icon: 'fa-ticket',
                     description: 'Sensíveis a desconto: já usaram cupom em alguma compra.',
                     rules: rules(cond('coupons_used', 'gte', '1')) },
        'email_ok' => { name: 'Podem receber e-mail', popular: false, icon: 'fa-envelope-circle-check',
                        description: 'Têm e-mail e não estão na lista de recusa.',
                        rules: rules(cond('has_email', 'yes'), cond('suppressed', 'no')) }
      }
    end
  end
end
