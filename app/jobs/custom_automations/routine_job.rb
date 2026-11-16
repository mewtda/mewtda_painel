module CustomAutomations
  # Roda as rotinas personalizadas por cliente (Registry::ROUTINES).
  #
  #   RoutineJob.perform_later                       # todas as rotinas, todos os clientes
  #   RoutineJob.perform_later('oneway_address_number_fix')  # uma rotina, todos os clientes dela
  #   RoutineJob.perform_later('oneway_address_number_fix', 34) # uma rotina, um cliente
  #
  # Sem client_id, só distribui: enfileira um job por (rotina, cliente), assim
  # o erro de um cliente não derruba os outros e cada um tem seu retry.
  class RoutineJob < ApplicationJob
    queue_as :default

    def perform(kind = nil, client_id = nil)
      return run(kind, Client.find(client_id)) if kind && client_id

      kinds = kind ? [kind.to_s] : Registry::ROUTINES.keys
      Client.where(active: true).find_each do |client|
        next unless client.shopify_configured?

        (Registry.routines_for(client).keys & kinds).each do |routine_kind|
          self.class.perform_later(routine_kind, client.id)
        end
      end
    end

    private

    def run(kind, client)
      config = Registry.routine(kind)
      raise ArgumentError, "Rotina desconhecida: #{kind}" unless config
      return unless client.active? && client.shopify_configured?
      return unless Registry.routines_for(client).key?(kind.to_s)

      config[:service].constantize.new(client, **config.fetch(:options, {})).call
    end
  end
end
