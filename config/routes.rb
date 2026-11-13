require 'sidekiq/web'

Rails.application.routes.draw do
  root to: 'home#index'

  # Páginas públicas de produto (mesma família visual da landing)
  get 'sua-loja',     to: 'home#sites', as: :sua_loja
  get 'app',          to: 'home#app_page', as: :app_page
  get 'meu-crm',      to: 'home#crm_page', as: :meu_crm

  # Política de privacidade usada nos apps (lojas da Apple/Google exigem URL pública)
  get 'privacidade',  to: 'home#privacy', as: :privacy
  get 'privacy',      to: redirect('/privacidade?locale=en')

  # O Pode Trocar (ex-Quero Trocar) agora tem site próprio
  get 'quero-trocar', to: redirect('https://www.podetrocar.com.br/')

  namespace :integrations do
    match 'shopify/events', to: 'shopify_events#create', via: [:post, :options]
  end

  # Webhook da Evolution API: autenticado pelo token do número, fora do CRM.
  post 'whatsapp/webhooks/:instance_key', to: 'whatsapp/webhooks#create'

  namespace :widget do
    get  'popup/config',      to: 'popup#show_config'
    post 'popup/submissions', to: 'popup#create_submission'
    get  'back_in_stock/config', to: 'back_in_stock#show_config'
    post 'back_in_stock/alerts', to: 'back_in_stock#create_alert'
    get  'back_in_stock/descadastrar/:token', to: 'back_in_stock_unsubscribes#show', as: :back_in_stock_unsubscribe
    post 'back_in_stock/descadastrar/:token', to: 'back_in_stock_unsubscribes#create'
    get  'descadastrar/:token', to: 'email_unsubscribes#show', as: :email_unsubscribe
    post 'descadastrar/:token', to: 'email_unsubscribes#create'
  end

  scope '/crm' do
    devise_for :user, skip: [:registrations]

    authenticate :user do
      mount Sidekiq::Web => '/sidekiq'
    end

    resources :try_on, only: [:index, :create] do
      collection do
        get :status
      end
    end

    resources :clients do
      namespace :whatsapp, module: 'whatsapp' do
        resources :connections, only: %i[index create update destroy] do
          member do
            post :connect
            post :disconnect
            post :sync
          end
        end
      end
    end
    # Atendimento: conversas do cliente selecionado, só nos números liberados ao usuário.
    namespace :whatsapp do
      resources :conversations, only: %i[index show create update] do
        member do
          post :read
          patch :auto_reply
        end
        resources :messages, only: %i[index create] do
          member do
            post :retry_send
            get :attachment
          end
        end
      end
    end

    resources :automations, only: [] do
      resources :actions, controller: 'automation_actions', only: :index do
        post :resend, on: :member
      end
    end

    get 'campaigns', to: redirect('/crm/automations'), as: nil
    get 'campaigns/:id', to: redirect('/crm/automations/%{id}/actions'), as: nil

    get   'automations',                    to: 'automations#index',           as: :automations
    get   'automations/tracking',           to: 'automations#edit_tracking',   as: :edit_tracking_automation
    patch 'automations/tracking',           to: 'automations#update_tracking', as: :tracking_automation
    get   'automations/cashback',           to: 'automations#edit_cashback',   as: :edit_cashback_automation
    patch 'automations/cashback',           to: 'automations#update_cashback', as: :cashback_automation
    get   'automations/cart-recovery',      to: 'automations#edit_cart_recovery',   as: :edit_cart_recovery_automation
    patch 'automations/cart-recovery',      to: 'automations#update_cart_recovery', as: :cart_recovery_automation
    get   'automations/cart-recovery/data', to: 'automations#cart_recovery_data',
                                            as: :cart_recovery_data_automation
    patch 'automations/:kind/numbers',      to: 'automations#update_numbers', as: :automation_numbers,
                                            constraints: { kind: /tracking|cashback|cart-recovery/ }
    post  'automations/cart-recovery/data/:id/resend', to: 'automations#resend_cart_recovery',
                                                       as: :resend_cart_recovery_automation

    resources :custom_automations, path: 'custom-automations', only: [:index, :new, :create, :show] do
      member do
        get  :spreadsheet
        post :emit
        post :discard
      end
    end

    resources :events, only: [:index] do
      collection do
        get  'session/:session_id', action: :session_detail, as: :session
        post 'generate_link',       action: :generate_link,  as: :generate_link
      end
    end

    resources :affiliates do
      collection do
        get   'configuracoes', action: :edit_settings,   as: :settings
        patch 'configuracoes', action: :update_settings, as: nil
      end
    end

    post 'update_selected_client', to: 'clients#update_selected_client'
    get '/', to: 'dashboard#index', as: :crm
    get '/session/:session_id', to: 'dashboard#session_detail', as: :crm_session

    get 'clients/:id/shopify/auth', to: 'shopify_auth#auth', as: :client_shopify_auth
    get '/shopify/callback', to: 'shopify_auth#callback'

    get    'clients/:id/google_ads/connect', to: 'google_ads#connect', as: :client_google_ads_connect
    get    'google_ads/callback', to: 'google_ads#callback', as: :google_ads_callback
    delete 'clients/:id/google_ads/disconnect', to: 'google_ads#disconnect', as: :client_google_ads_disconnect

    resources :dashboard, only: [:index]

    get  'vendas',               to: 'sales_dashboard#index', as: :sales_dashboard
    get  'vendas/export_xlsx',   to: 'sales_dashboard#export_xlsx',   as: :export_xlsx_sales_dashboard
    post 'vendas/sync_ad_costs', to: 'sales_dashboard#sync_ad_costs', as: :sync_ad_costs_sales_dashboard
    post 'vendas/process_now',   to: 'sales_dashboard#process_now',   as: :process_now_sales_dashboard
    get  'vendas/orders_for_day', to: 'sales_dashboard#orders_for_day', as: :orders_for_day_sales_dashboard
    get  'vendas/devolucoes',     to: 'sales_dashboard#returns',        as: :returns_sales_dashboard

    resources :ad_costs, except: [:show]
    resource :goal, only: %i[edit update]
    resource :popup, only: %i[edit update]
    resources :landing_pages, path: 'landing-pages' do
      post :sync_products, on: :member
    end
    get 'popup/cadastros', to: 'popups#submissions', as: :submissions_popup

    resource :back_in_stock, path: 'de-volta-ao-estoque', controller: 'back_in_stock', only: %i[show create update] do
      patch :regenerate_token, path: 'novo-token'
      patch 'alertas/:alert_id/cancelar', action: :cancel_alert, as: :cancel_alert
    end

    resources :email_templates, except: [:show] do
      collection do
        post :preview
        post :send_test
        post :upload_image
      end
    end
    resources :email_suppressions, path: 'lista-de-recusa', only: %i[index create destroy]
    resources :campaigns, path: 'campanhas', only: %i[index create edit update destroy] do
      member do
        get :preview
        post :send_test
        post :schedule
        post :cancel
      end
    end
    resource :email_configuration, only: %i[edit update]
    post 'email_configuration/refresh', to: 'email_configurations#refresh_status', as: :refresh_email_configuration

    resource :settings, path: 'configuracoes', controller: 'settings', only: [:edit, :update]
    resource :account, path: 'minha-conta', controller: 'account', only: [:edit, :update] do
      get :limits, path: 'limites'
      get :invoice, path: 'fatura'
    end

    resources :orders, only: [:index] do
      collection do
        get :export_xlsx
      end
      member do
        get :details
      end
    end

    resources :products, only: [:index] do
      collection do
        get :export_xlsx
      end
    end

    resources :customers, only: [:index] do
      collection do
        get :export_xlsx
        get :rfm, path: 'matriz-rfm'
        post :add_to_list
      end
      member do
        get :details
      end
    end
    resources :segments, path: 'segmentos', except: [:show] do
      collection do
        get :templates, path: 'sugeridos'
        post :preview
      end
      member do
        post :recount
        post :duplicate
      end
    end

    resources :users do
      member do
        patch :reset_password
      end
    end
    resources :profiles

    resources :attempts, only: [:index] do
      collection do
        get :verify_attempts
      end
    end
  end

  # Landing pages públicas — /:path_prefix/:slug (ex.: /use1822/drop-01).
  # Fica por último pra nunca sombrear uma rota do app; prefixos reservados
  # (LandingPage::RESERVED_PREFIXES) são recusados no model e no controller.
  constraints(path_prefix: /[a-z0-9]+(?:-[a-z0-9]+)*/, slug: /[a-z0-9]+(?:-[a-z0-9]+)*/) do
    get  '/:path_prefix/:slug',      to: 'public_landing_pages#show', as: :public_landing_page
    post '/:path_prefix/:slug/lead', to: 'public_landing_pages#lead', as: :public_landing_page_lead
    post '/:path_prefix/:slug/break', to: 'public_landing_pages#break_chain', as: :public_landing_page_break
  end
end
