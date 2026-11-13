# Garante que a base de perfis (customer_profiles) da loja exista antes de
# telas que dependem dela (Clientes, Segmentos).
#
# Primeira visita calcula na hora (e reconta os segmentos); depois, se estiver
# velha, recalcula em segundo plano.
module EnsuresCustomerProfiles
  extend ActiveSupport::Concern

  PROFILES_STALE_AFTER = 1.hour

  private

  def ensure_profiles
    last = @client.customer_profiles.maximum(:refreshed_at)
    if last.nil?
      if Order.where(client_id: @client.id).exists?
        Customers::RefreshProfiles.new(@client).call
        @client.segments.find_each(&:recount!)
      end
    elsif last < PROFILES_STALE_AFTER.ago
      Customers::RefreshProfilesJob.perform_later(@client.id)
    end
    @refreshed_at = @client.customer_profiles.maximum(:refreshed_at)
  end
end
