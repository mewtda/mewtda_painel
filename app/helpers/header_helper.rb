module HeaderHelper
  # Lista de telas/menus buscáveis na navbar. Espelha manualmente as mesmas
  # condicionais de visibilidade de app/views/layouts/partials/_sidebar.html.erb
  # e do dropdown de usuário em _header.html.erb — não é gerada a partir deles,
  # então qualquer mudança de visibilidade de menu precisa ser replicada aqui.
  def searchable_nav_items(user)
    return affiliate_nav_items(user) if user.profile_id == Profile::AFFILIATE

    items = [{ label: 'Trackeamento site', url: crm_path, icon: 'fa-solid fa-chart-line' }]

    if user.admin? || user.client.present?
      items << { label: 'Vendas', url: sales_dashboard_path, icon: 'fa-solid fa-sack-dollar' }
    end

    items += [
      { label: 'Pedidos', url: orders_path, icon: 'fa-solid fa-box' },
      { label: 'Clientes', url: customers_path, icon: 'fa-solid fa-users' },
      { label: 'Segmentos e listas', url: segments_path, icon: 'fa-solid fa-layer-group' },
      { label: 'Campanhas', url: campaigns_path, icon: 'fa-solid fa-bullhorn' },
      { label: 'Produtos', url: products_path, icon: 'fa-solid fa-bag-shopping' },
      { label: 'De volta ao estoque', url: back_in_stock_path, icon: 'fa-solid fa-bell' },
      { label: 'Modelos de mensagem', url: email_templates_path, icon: 'fa-solid fa-envelope-open-text' },
      { label: 'Afiliados', url: affiliates_path, icon: 'fa-solid fa-user-group' },
      { label: 'Automações', url: crm_path, icon: 'fa-solid fa-robot' },
      { label: 'Automações personalizadas', url: custom_automations_path, icon: 'fa-solid fa-wand-magic-sparkles' }
    ]

    items += user.admin? ? admin_nav_items : [
      { label: 'Configurações', url: edit_settings_path, icon: 'fa-solid fa-gear' },
      { label: 'Custos de Anúncio', url: ad_costs_path, icon: 'fa-solid fa-money-bill-wave' },
      { label: 'Metas', url: edit_goal_path, icon: 'fa-solid fa-bullseye' }
    ]

    items
  end

  # Cliente que aparece no seletor da sidebar e no breadcrumb: o escolhido
  # pelo admin (session[:selected_client_id]) ou o do próprio lojista.
  def crm_current_client
    return current_user.client unless current_user.admin?

    @crm_current_client ||= Client.find_by(id: session[:selected_client_id]) if session[:selected_client_id].present?
  end

  # Quadradinho com a inicial do cliente, como os workspaces do ClickUp (mesmas
  # cores do Rainbow).
  WS_BADGE_HUES = %w[#ff5f6d #ffb347 #e6c800 #3ccf8e #5ab9ff #8f7cff #e17cff].freeze

  def ws_badge(name)
    name = name.to_s.strip.presence || '?'
    color = WS_BADGE_HUES[name.sum % WS_BADGE_HUES.size]
    content_tag(:span, name[0].upcase, class: 'crm-ws__badge', style: "background: #{color}")
  end

  private

  def affiliate_nav_items(user)
    [{ label: 'Meus Eventos', url: events_path(utm_code: user.utm_code), icon: 'fa-solid fa-chart-line' }]
  end

  def admin_nav_items
    [
      { label: 'Usuários', url: users_path, icon: 'fa-solid fa-user' },
      { label: 'Clientes', url: clients_path, icon: 'fa-solid fa-building' },
      { label: 'Perfis', url: profiles_path, icon: 'fa-solid fa-id-badge' },
      { label: 'Custos de Anúncio', url: ad_costs_path, icon: 'fa-solid fa-money-bill-wave' },
      { label: 'Metas', url: edit_goal_path, icon: 'fa-solid fa-bullseye' },
      { label: 'Sidekiq', url: '/crm/sidekiq', icon: 'fa-solid fa-bolt' },
      { label: 'Try-On Virtual', url: try_on_index_path, icon: 'fa-solid fa-wand-magic-sparkles' }
    ]
  end
end
