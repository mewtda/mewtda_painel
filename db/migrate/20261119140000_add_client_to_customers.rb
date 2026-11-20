class AddClientToCustomers < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    # Loja de origem do cliente importado da Shopify (inclusive quem nunca comprou).
    # Clientes que só vieram pelos pedidos continuam ligados à loja via orders.
    add_reference :customers, :client, index: { algorithm: :concurrently }, foreign_key: { validate: false }
    # Última sincronização completa/incremental dos clientes da Shopify (Customers::SyncJob).
    add_column :clients, :customers_synced_at, :datetime
  end
end
