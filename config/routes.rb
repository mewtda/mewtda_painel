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

    resources :campaigns do
      resources :campaign_actions, only: [:index, :show], path: 'actions'
    end
    post 'campaigns/:campaign_id/actions/:action_id/resend', to: 'campaigns#resend_action', as: :resend_campaign_action

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

    resources :email_templates, except: [:show]
    resource :email_configuration, only: %i[edit update]
    post 'email_configuration/refresh', to: 'email_configurations#refresh_status', as: :refresh_email_configuration

    resource :settings, path: 'configuracoes', controller: 'settings', only: [:edit, :update]
    resource :account, path: 'minha-conta', controller: 'account', only: [:edit, :update]

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
      end
      member do
        get :details
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
