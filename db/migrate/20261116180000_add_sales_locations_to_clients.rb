class AddSalesLocationsToClients < ActiveRecord::Migration[7.2]
  def change
    # Locations da Shopify consideradas nos relatórios (vazio = todas).
    # Substitui o filtro por canal de venda (clients.sales_channels, sem uso).
    add_column :clients, :sales_locations, :string, array: true, default: [], null: false
  end
end
