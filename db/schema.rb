# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2026_11_04_150000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "abandoned_checkouts", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.bigint "customer_id"
    t.string "shopify_checkout_id", null: false
    t.string "shopify_checkout_token"
    t.string "email"
    t.string "phone"
    t.decimal "total_price", precision: 12, scale: 2
    t.string "currency"
    t.datetime "checkout_created_at"
    t.datetime "checkout_updated_at"
    t.string "recovery_url"
    t.datetime "completed_at"
    t.jsonb "line_items", default: []
    t.datetime "first_notified_at"
    t.text "first_message_sent"
    t.string "first_coupon_code"
    t.datetime "second_notified_at"
    t.text "second_message_sent"
    t.string "second_coupon_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug"
    t.string "whatsapp_provider"
    t.string "skip_reason"
    t.bigint "whatsapp_connection_id"
    t.bigint "whatsapp_conversation_id"
    t.index ["client_id", "shopify_checkout_id"], name: "index_abandoned_checkouts_on_client_and_shopify_id", unique: true
    t.index ["client_id"], name: "index_abandoned_checkouts_on_client_id"
    t.index ["customer_id"], name: "index_abandoned_checkouts_on_customer_id"
    t.index ["slug"], name: "index_abandoned_checkouts_on_slug", unique: true
    t.index ["whatsapp_connection_id"], name: "index_abandoned_checkouts_on_whatsapp_connection_id"
    t.index ["whatsapp_conversation_id"], name: "index_abandoned_checkouts_on_whatsapp_conversation_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ad_cost_snapshots", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.string "platform", null: false
    t.integer "year", null: false
    t.integer "month", null: false
    t.decimal "cost", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "fetched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "platform", "year", "month"], name: "index_ad_cost_snapshots_on_client_platform_month", unique: true
    t.index ["client_id"], name: "index_ad_cost_snapshots_on_client_id"
  end

  create_table "ad_costs", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.string "platform", null: false
    t.string "name", null: false
    t.date "start_date", null: false
    t.date "end_date", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "platform"], name: "index_ad_costs_on_client_id_and_platform"
    t.index ["client_id", "start_date", "end_date"], name: "index_ad_costs_on_client_id_and_start_date_and_end_date"
    t.index ["client_id"], name: "index_ad_costs_on_client_id"
  end

  create_table "attempts", force: :cascade do |t|
    t.bigint "kinds"
    t.bigint "status"
    t.text "requisition"
    t.text "params"
    t.string "error"
    t.string "status_code"
    t.string "message"
    t.string "exception"
    t.string "classification"
    t.string "cause"
    t.string "url"
    t.string "user"
    t.integer "bling_order_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "campaign_actions", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "customer_id", null: false
    t.bigint "order_id"
    t.integer "kind", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.text "message_sent"
    t.datetime "notified_at"
    t.text "response"
    t.text "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "slug"
    t.index ["campaign_id", "kind"], name: "index_campaign_actions_on_campaign_id_and_kind"
    t.index ["campaign_id", "status"], name: "index_campaign_actions_on_campaign_id_and_status"
    t.index ["campaign_id"], name: "index_campaign_actions_on_campaign_id"
    t.index ["customer_id"], name: "index_campaign_actions_on_customer_id"
    t.index ["notified_at"], name: "index_campaign_actions_on_notified_at"
    t.index ["order_id"], name: "index_campaign_actions_on_order_id"
    t.index ["slug"], name: "index_campaign_actions_on_slug", unique: true
  end

  create_table "campaigns", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.string "name", null: false
    t.integer "kind", default: 0, null: false
    t.text "message"
    t.integer "days_after_purchase", default: 7
    t.date "start_date"
    t.date "end_date"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "filters", default: {}, null: false
    t.integer "max_sends"
    t.integer "interval_days"
    t.integer "send_delay_minutes"
    t.boolean "include_coupon", default: false, null: false
    t.boolean "resend_enabled", default: false, null: false
    t.integer "resend_delay_hours"
    t.text "resend_message"
    t.boolean "resend_include_coupon", default: false, null: false
    t.string "coupon_code"
    t.string "resend_coupon_code"
    t.string "slug"
    t.datetime "evolution_started_at"
    t.index ["client_id", "kind"], name: "index_campaigns_on_client_id_and_kind"
    t.index ["client_id"], name: "index_campaigns_on_client_id"
    t.index ["filters"], name: "index_campaigns_on_filters", using: :gin
    t.index ["slug"], name: "index_campaigns_on_slug", unique: true
    t.index ["start_date", "end_date"], name: "index_campaigns_on_start_date_and_end_date"
  end

  create_table "clients", force: :cascade do |t|
    t.string "name"
    t.string "email"
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "shopify_shop_url"
    t.string "shopify_access_token"
    t.string "zapi_instance_id"
    t.string "zapi_instance_token"
    t.string "zapi_client_token"
    t.string "meta_access_token"
    t.string "meta_ad_account_id"
    t.string "google_ads_customer_id"
    t.string "google_ads_refresh_token"
    t.datetime "google_ads_connected_at"
    t.string "shopify_api_key"
    t.string "shopify_api_secret"
    t.datetime "orders_synced_at"
    t.datetime "refunds_synced_at"
    t.string "site_url"
    t.string "email_sending_domain"
    t.string "ses_verification_status", default: "unverified", null: false
    t.string "ses_dkim_tokens", default: [], null: false, array: true
    t.datetime "ses_verified_at"
    t.string "slug"
    t.string "shopify_storefront_token"
    t.string "whatsapp_cloud_phone_number_id"
    t.string "whatsapp_cloud_business_account_id"
    t.text "whatsapp_cloud_access_token"
    t.string "whatsapp_provider", default: "zapi", null: false
    t.boolean "auto_reply_enabled", default: false, null: false
    t.text "openai_api_key"
    t.string "openai_model"
    t.text "auto_reply_instructions"
    t.index ["shopify_shop_url"], name: "index_clients_on_shopify_shop_url", unique: true
    t.index ["slug"], name: "index_clients_on_slug", unique: true
  end

  create_table "custom_automation_runs", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.bigint "user_id"
    t.string "kind", null: false
    t.string "status", default: "pending", null: false
    t.date "period_start", null: false
    t.date "period_end", null: false
    t.string "order_filter", null: false
    t.decimal "price_percentage", precision: 5, scale: 2, null: false
    t.integer "orders_count", default: 0, null: false
    t.decimal "total_value", precision: 14, scale: 2, default: "0.0", null: false
    t.jsonb "items", default: [], null: false
    t.jsonb "warnings", default: [], null: false
    t.string "tiny_note_id"
    t.string "tiny_note_number"
    t.text "tiny_response"
    t.text "error_message"
    t.datetime "emitted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "kind", "created_at"], name: "idx_on_client_id_kind_created_at_22125b7406"
    t.index ["client_id"], name: "index_custom_automation_runs_on_client_id"
    t.index ["user_id"], name: "index_custom_automation_runs_on_user_id"
  end

  create_table "customers", force: :cascade do |t|
    t.string "shopify_customer_id"
    t.string "name"
    t.string "email"
    t.string "phone"
    t.string "first_name"
    t.string "last_name"
    t.string "currency"
    t.text "tags"
    t.integer "orders_count"
    t.decimal "total_spent", precision: 12, scale: 2
    t.boolean "verified_email"
    t.boolean "tax_exempt"
    t.datetime "shopify_created_at"
    t.datetime "shopify_updated_at"
    t.string "default_address_name"
    t.string "default_address_company"
    t.string "default_address_phone"
    t.string "default_address_address1"
    t.string "default_address_address2"
    t.string "default_address_city"
    t.string "default_address_province"
    t.string "default_address_country"
    t.string "default_address_zip"
    t.string "default_address_country_code"
    t.string "default_address_province_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "addresses", default: [], null: false
    t.index ["email"], name: "index_customers_on_email"
    t.index ["shopify_customer_id"], name: "index_customers_on_shopify_customer_id", unique: true
  end

  create_table "email_templates", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.string "name", null: false
    t.string "subject", null: false
    t.string "heading", null: false
    t.text "body", null: false
    t.string "button_text", null: false
    t.string "button_url"
    t.string "coupon_code"
    t.string "accent_color", default: "#7c3aed", null: false
    t.string "layout", default: "image_top", null: false
    t.integer "trigger_kind", default: 0, null: false
    t.jsonb "trigger_config", default: {}, null: false
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_email_templates_on_client_id"
  end

  create_table "goals", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.integer "year", null: false
    t.integer "month", null: false
    t.decimal "revenue_target", precision: 12, scale: 2
    t.decimal "roas_target", precision: 6, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "avg_ticket_target", precision: 12, scale: 2
    t.decimal "conversion_rate_target", precision: 6, scale: 2
    t.decimal "cac_target", precision: 12, scale: 2
    t.decimal "tagged_revenue_target", precision: 12, scale: 2
    t.string "tagged_revenue_tag"
    t.index ["client_id", "year", "month"], name: "index_goals_on_client_id_and_year_and_month", unique: true
    t.index ["client_id"], name: "index_goals_on_client_id"
  end

  create_table "integration_users", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.string "api_secret", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "client_id", null: false
    t.index ["client_id"], name: "index_integration_users_on_client_id"
    t.index ["slug"], name: "index_integration_users_on_slug", unique: true
  end

  create_table "landing_page_leads", force: :cascade do |t|
    t.bigint "landing_page_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.string "phone"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_term"
    t.boolean "existing_customer", default: false, null: false
    t.string "shopify_customer_id"
    t.string "status", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["landing_page_id", "email"], name: "index_landing_page_leads_on_landing_page_id_and_email", unique: true
    t.index ["landing_page_id"], name: "index_landing_page_leads_on_landing_page_id"
  end

  create_table "landing_pages", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.string "name", null: false
    t.string "path_prefix", null: false
    t.string "slug", null: false
    t.string "template", null: false
    t.boolean "active", default: false, null: false
    t.datetime "ends_at"
    t.string "product_handles", default: [], null: false, array: true
    t.integer "views_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "chain_breaks_count", default: 0, null: false
    t.jsonb "storefront_cache", default: {}, null: false
    t.datetime "storefront_synced_at"
    t.index ["client_id"], name: "index_landing_pages_on_client_id"
    t.index ["path_prefix", "slug"], name: "index_landing_pages_on_path_prefix_and_slug", unique: true
  end

  create_table "locations", force: :cascade do |t|
    t.string "slug"
    t.string "name"
    t.decimal "kpi_ratio", precision: 10, scale: 4
    t.datetime "kpi_updated_at"
    t.string "shopify_location_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "client_id"
    t.index ["client_id"], name: "index_locations_on_client_id"
    t.index ["shopify_location_id"], name: "index_locations_on_shopify_location_id", unique: true
    t.index ["slug"], name: "index_locations_on_slug", unique: true
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_id"
    t.decimal "price", precision: 10, scale: 2
    t.integer "quantity"
    t.string "sku"
    t.boolean "canceled", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "location_id"
    t.bigint "customer_id"
    t.string "shopify_order_id"
    t.string "shopify_order_number"
    t.string "kinds"
    t.text "tags"
    t.integer "staff_id"
    t.string "staff_name"
    t.datetime "shopify_creation_date"
    t.jsonb "payments", default: []
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "client_id"
    t.decimal "subtotal_price", precision: 12, scale: 2
    t.decimal "total_discounts", precision: 12, scale: 2
    t.decimal "total_price", precision: 12, scale: 2
    t.datetime "cancelled_at"
    t.decimal "total_shipping_price", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_tax", precision: 12, scale: 2, default: "0.0", null: false
    t.string "tracking_number"
    t.string "tracking_company"
    t.string "tracking_url"
    t.datetime "fulfilled_at"
    t.string "discount_code"
    t.bigint "landing_page_id"
    t.index ["cancelled_at"], name: "index_orders_on_cancelled_at"
    t.index ["client_id", "shopify_order_id"], name: "index_orders_on_client_id_and_shopify_order_id", unique: true
    t.index ["client_id"], name: "index_orders_on_client_id"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["discount_code"], name: "index_orders_on_discount_code"
    t.index ["landing_page_id"], name: "index_orders_on_landing_page_id"
    t.index ["location_id"], name: "index_orders_on_location_id"
    t.index ["shopify_order_id"], name: "index_orders_on_shopify_order_id", unique: true
    t.index ["shopify_order_number"], name: "index_orders_on_shopify_order_number"
  end

  create_table "popup_submissions", force: :cascade do |t|
    t.bigint "popup_id", null: false
    t.string "name", null: false
    t.string "email", null: false
    t.string "phone"
    t.string "shopify_customer_id"
    t.string "status", default: "success", null: false
    t.datetime "created_at", null: false
    t.index ["popup_id", "status"], name: "index_popup_submissions_on_popup_id_and_status"
    t.index ["popup_id"], name: "index_popup_submissions_on_popup_id"
  end

  create_table "popups", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.boolean "active", default: false, null: false
    t.string "title"
    t.text "description"
    t.string "coupon_code"
    t.string "button_text", default: "Cadastrar", null: false
    t.string "accent_color", default: "#7c3aed", null: false
    t.string "template", default: "template_1", null: false
    t.string "size", default: "medium", null: false
    t.integer "reappear_after_hours", default: 24, null: false
    t.string "public_token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_popups_on_client_id", unique: true
    t.index ["public_token"], name: "index_popups_on_public_token", unique: true
  end

  create_table "products", force: :cascade do |t|
    t.string "sku"
    t.string "shopify_product_id"
    t.string "shopify_variant_id"
    t.string "shopify_inventory_item_id"
    t.string "shopify_product_name"
    t.decimal "cost", precision: 10, scale: 2
    t.decimal "price", precision: 10, scale: 2
    t.decimal "compare_at_price", precision: 10, scale: 2
    t.string "vendor"
    t.string "option1"
    t.string "option2"
    t.string "option3"
    t.text "tags"
    t.string "image_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "client_id"
    t.index ["client_id", "shopify_variant_id"], name: "index_products_on_client_and_variant", unique: true
    t.index ["client_id"], name: "index_products_on_client_id"
    t.index ["shopify_inventory_item_id"], name: "index_products_on_shopify_inventory_item_id"
    t.index ["shopify_product_id"], name: "index_products_on_shopify_product_id"
    t.index ["sku"], name: "index_products_on_sku"
  end

  create_table "profiles", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "refunds", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.bigint "order_id"
    t.string "shopify_refund_id", null: false
    t.string "shopify_order_id", null: false
    t.datetime "processed_at", null: false
    t.decimal "amount", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "processed_at"], name: "index_refunds_on_client_id_and_processed_at"
    t.index ["client_id", "shopify_refund_id"], name: "index_refunds_on_client_id_and_shopify_refund_id", unique: true
    t.index ["client_id"], name: "index_refunds_on_client_id"
    t.index ["order_id"], name: "index_refunds_on_order_id"
  end

  create_table "shopify_events", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.bigint "integration_user_id", null: false
    t.string "kind"
    t.string "session_id"
    t.string "shopify_event_id"
    t.jsonb "payload", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "event_id"
    t.string "event_name"
    t.string "event_type"
    t.string "shop_domain"
    t.datetime "event_timestamp"
    t.jsonb "data"
    t.jsonb "context"
    t.jsonb "raw_payload"
    t.index ["client_id", "created_at"], name: "index_shopify_events_on_client_id_and_created_at"
    t.index ["client_id", "kind"], name: "index_shopify_events_on_client_id_and_kind"
    t.index ["client_id"], name: "index_shopify_events_on_client_id"
    t.index ["event_name"], name: "index_shopify_events_on_event_name"
    t.index ["event_timestamp"], name: "index_shopify_events_on_event_timestamp"
    t.index ["integration_user_id"], name: "index_shopify_events_on_integration_user_id"
    t.index ["kind"], name: "index_shopify_events_on_kind"
    t.index ["session_id", "event_name"], name: "index_shopify_events_on_session_id_and_event_name"
    t.index ["session_id"], name: "index_shopify_events_on_session_id"
    t.index ["shop_domain", "kind"], name: "index_shopify_events_on_shop_domain_and_kind"
    t.index ["shop_domain"], name: "index_shopify_events_on_shop_domain"
    t.index ["shopify_event_id"], name: "index_shopify_events_on_shopify_event_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "name"
    t.string "phone"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.string "unlock_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "profile_id"
    t.bigint "client_id"
    t.string "utm_code"
    t.string "discount_code"
    t.index ["client_id"], name: "index_users_on_client_id"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["discount_code"], name: "index_users_on_discount_code"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["profile_id"], name: "index_users_on_profile_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.index ["utm_code"], name: "index_users_on_utm_code", unique: true
  end

  create_table "whatsapp_campaign_connections", force: :cascade do |t|
    t.bigint "campaign_id", null: false
    t.bigint "connection_id", null: false
    t.datetime "last_assigned_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["campaign_id", "connection_id"], name: "idx_wa_campaign_connection_unique", unique: true
    t.index ["campaign_id"], name: "index_whatsapp_campaign_connections_on_campaign_id"
    t.index ["connection_id"], name: "index_whatsapp_campaign_connections_on_connection_id"
  end

  create_table "whatsapp_connections", force: :cascade do |t|
    t.bigint "client_id", null: false
    t.string "name", null: false
    t.string "provider", default: "evolution", null: false
    t.string "instance_key", null: false
    t.text "webhook_token", null: false
    t.string "phone"
    t.string "state", default: "disconnected", null: false
    t.boolean "enabled", default: true, null: false
    t.text "qr_data"
    t.datetime "qr_expires_at"
    t.datetime "provider_updated_at"
    t.datetime "last_event_at"
    t.datetime "last_synced_at"
    t.datetime "sync_requested_at"
    t.string "control_action"
    t.integer "control_version", default: 0, null: false
    t.string "error_code"
    t.datetime "next_send_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_whatsapp_connections_on_client_id"
    t.index ["instance_key"], name: "index_whatsapp_connections_on_instance_key", unique: true
  end

  create_table "whatsapp_contact_aliases", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.bigint "contact_id", null: false
    t.string "jid", limit: 191, null: false
    t.index ["connection_id", "jid"], name: "idx_wa_alias_unique", unique: true
    t.index ["connection_id"], name: "index_whatsapp_contact_aliases_on_connection_id"
    t.index ["contact_id"], name: "index_whatsapp_contact_aliases_on_contact_id"
  end

  create_table "whatsapp_contacts", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.bigint "customer_id"
    t.string "provider_jid", limit: 191, null: false
    t.string "phone"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "provider_jid"], name: "idx_wa_contact_unique", unique: true
    t.index ["connection_id"], name: "index_whatsapp_contacts_on_connection_id"
    t.index ["customer_id"], name: "index_whatsapp_contacts_on_customer_id"
    t.index ["phone"], name: "index_whatsapp_contacts_on_phone"
  end

  create_table "whatsapp_conversations", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.bigint "contact_id", null: false
    t.string "state", default: "open", null: false
    t.datetime "last_message_at"
    t.string "last_message_preview"
    t.boolean "auto_reply_paused", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "contact_id"], name: "idx_wa_conversation_unique", unique: true
    t.index ["connection_id", "last_message_at"], name: "idx_wa_inbox"
    t.index ["connection_id"], name: "index_whatsapp_conversations_on_connection_id"
    t.index ["contact_id"], name: "index_whatsapp_conversations_on_contact_id"
  end

  create_table "whatsapp_events", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.string "digest", limit: 64, null: false
    t.string "kind", null: false
    t.text "payload", null: false
    t.datetime "occurred_at", null: false
    t.datetime "processed_at"
    t.integer "attempts", default: 0, null: false
    t.string "error_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "digest"], name: "idx_wa_event_unique", unique: true
    t.index ["connection_id"], name: "index_whatsapp_events_on_connection_id"
    t.index ["processed_at", "attempts"], name: "idx_wa_pending_events"
  end

  create_table "whatsapp_media", force: :cascade do |t|
    t.bigint "message_id", null: false
    t.string "storage_key", null: false
    t.string "service_name", null: false
    t.string "filename", null: false
    t.string "content_type", null: false
    t.bigint "byte_size", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_whatsapp_media_on_message_id", unique: true
    t.index ["storage_key"], name: "index_whatsapp_media_on_storage_key", unique: true
  end

  create_table "whatsapp_memberships", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.bigint "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "user_id"], name: "idx_wa_membership_unique", unique: true
    t.index ["connection_id"], name: "index_whatsapp_memberships_on_connection_id"
    t.index ["user_id"], name: "index_whatsapp_memberships_on_user_id"
  end

  create_table "whatsapp_messages", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.bigint "conversation_id", null: false
    t.bigint "user_id"
    t.string "provider_id", limit: 191
    t.string "client_nonce", limit: 64
    t.string "direction", null: false
    t.string "kind", default: "text", null: false
    t.text "body"
    t.string "state", null: false
    t.integer "receipt_rank", default: 0, null: false
    t.boolean "historical", default: false, null: false
    t.datetime "sent_at", null: false
    t.datetime "attempted_at"
    t.string "error_code"
    t.string "media_state"
    t.integer "media_attempts", default: 0, null: false
    t.datetime "media_retry_at"
    t.jsonb "provider_key"
    t.string "origin", default: "team", null: false
    t.datetime "send_after"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "client_nonce"], name: "idx_wa_client_message", unique: true
    t.index ["connection_id", "provider_id"], name: "idx_wa_provider_message", unique: true
    t.index ["connection_id"], name: "index_whatsapp_messages_on_connection_id"
    t.index ["conversation_id", "sent_at", "id"], name: "idx_wa_history"
    t.index ["conversation_id"], name: "index_whatsapp_messages_on_conversation_id"
    t.index ["media_state", "media_retry_at"], name: "idx_wa_pending_media"
    t.index ["state", "attempted_at"], name: "idx_wa_pending_sends"
    t.index ["user_id"], name: "index_whatsapp_messages_on_user_id"
  end

  create_table "whatsapp_reads", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "user_id", null: false
    t.bigint "last_message_id", default: 0, null: false
    t.index ["conversation_id", "user_id"], name: "idx_wa_read_unique", unique: true
    t.index ["conversation_id"], name: "index_whatsapp_reads_on_conversation_id"
    t.index ["user_id"], name: "index_whatsapp_reads_on_user_id"
  end

  create_table "whatsapp_receipts", force: :cascade do |t|
    t.bigint "connection_id", null: false
    t.string "provider_id", limit: 191, null: false
    t.integer "rank", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["connection_id", "provider_id"], name: "idx_wa_receipt_unique", unique: true
    t.index ["connection_id"], name: "index_whatsapp_receipts_on_connection_id"
  end

  add_foreign_key "abandoned_checkouts", "clients"
  add_foreign_key "abandoned_checkouts", "customers"
  add_foreign_key "abandoned_checkouts", "whatsapp_connections", on_delete: :nullify
  add_foreign_key "abandoned_checkouts", "whatsapp_conversations", on_delete: :nullify
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ad_cost_snapshots", "clients"
  add_foreign_key "ad_costs", "clients"
  add_foreign_key "campaign_actions", "campaigns"
  add_foreign_key "campaign_actions", "customers"
  add_foreign_key "campaign_actions", "orders"
  add_foreign_key "campaigns", "clients"
  add_foreign_key "custom_automation_runs", "clients"
  add_foreign_key "custom_automation_runs", "users"
  add_foreign_key "email_templates", "clients"
  add_foreign_key "goals", "clients"
  add_foreign_key "integration_users", "clients"
  add_foreign_key "landing_page_leads", "landing_pages"
  add_foreign_key "landing_pages", "clients"
  add_foreign_key "locations", "clients"
  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "clients"
  add_foreign_key "orders", "customers"
  add_foreign_key "orders", "landing_pages", on_delete: :nullify
  add_foreign_key "orders", "locations"
  add_foreign_key "popup_submissions", "popups"
  add_foreign_key "popups", "clients"
  add_foreign_key "products", "clients"
  add_foreign_key "refunds", "clients"
  add_foreign_key "refunds", "orders"
  add_foreign_key "shopify_events", "clients"
  add_foreign_key "shopify_events", "integration_users"
  add_foreign_key "users", "clients"
  add_foreign_key "users", "profiles"
  add_foreign_key "whatsapp_campaign_connections", "campaigns"
  add_foreign_key "whatsapp_campaign_connections", "whatsapp_connections", column: "connection_id"
  add_foreign_key "whatsapp_connections", "clients"
  add_foreign_key "whatsapp_contact_aliases", "whatsapp_connections", column: "connection_id"
  add_foreign_key "whatsapp_contact_aliases", "whatsapp_contacts", column: "contact_id"
  add_foreign_key "whatsapp_contacts", "whatsapp_connections", column: "connection_id"
  add_foreign_key "whatsapp_conversations", "whatsapp_connections", column: "connection_id"
  add_foreign_key "whatsapp_conversations", "whatsapp_contacts", column: "contact_id"
  add_foreign_key "whatsapp_events", "whatsapp_connections", column: "connection_id"
  add_foreign_key "whatsapp_media", "whatsapp_messages", column: "message_id"
  add_foreign_key "whatsapp_memberships", "users"
  add_foreign_key "whatsapp_memberships", "whatsapp_connections", column: "connection_id"
  add_foreign_key "whatsapp_messages", "users"
  add_foreign_key "whatsapp_messages", "whatsapp_connections", column: "connection_id"
  add_foreign_key "whatsapp_messages", "whatsapp_conversations", column: "conversation_id"
  add_foreign_key "whatsapp_reads", "users"
  add_foreign_key "whatsapp_reads", "whatsapp_conversations", column: "conversation_id"
  add_foreign_key "whatsapp_receipts", "whatsapp_connections", column: "connection_id"
end
