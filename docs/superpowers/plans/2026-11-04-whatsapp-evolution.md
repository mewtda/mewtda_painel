# WhatsApp via Evolution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clientes do CRM com "Evolution Mewtda" ligada enviam todo WhatsApp (recuperação de carrinho, cashback, rastreio) por números próprios conectados na Evolution, divididos por automação, com tela de conversas (texto e mídia) permissionada por número, ticket médio do carrinho abandonado e resposta automática OpenAI opcional.

**Architecture:** Porta a base de WhatsApp do Honey (`/Users/danielfernandes/projects/ChaseOrders`, namespace `Whatsapp::`) para o painel, sem nada de agente/IA do Honey, acrescentando `client_id` em `whatsapp_connections` como fronteira de isolamento. Todos os fluxos que hoje chamam `Zapi::Client` passam por `Whatsapp::Outbound`, que decide Z-API ou Evolution pelo cliente. Mensagens pela Evolution são uma outbox durável (`whatsapp_messages` em `queued`) enviada por `Whatsapp::SendJob` na fila `whatsapp`, num processo Sidekiq separado.

**Tech Stack:** Rails 7 / Postgres / Sidekiq 7 + sidekiq-cron / Active Storage em S3 (`aws-sdk-s3`) / Evolution API 2.3.7 (`mewtda-evolution`) / OpenAI Chat Completions via `Net::HTTP` / Minitest.

**Spec:** `docs/superpowers/specs/2026-11-04-recuperacao-carrinho-evolution-design.md`

## Global Constraints

- Evolution API **2.3.7**; URL/chave em `EVOLUTION_API_URL` / `EVOLUTION_API_KEY` (já setadas em produção e no `.env`). Webhooks apontam para `WHATSAPP_WEBHOOK_BASE_URL` (produção: `https://www.mewtda.com.br`).
- **Cada número pertence a um único cliente e só é usado no contexto dele** — garantido no modelo, não só na tela.
- **Nada do agente de IA do Honey**: não portar `agent*`, `automation*` (do Honey), `learned_template`, `activity`, `agent_job`, `resume_agent_job`, campos `agent_*`/`needs_human`/`stage` de IA. A única IA é a resposta automática OpenAI (Task 9).
- Cliente sem Evolution continua **exatamente** como hoje (Z-API).
- Mensagem de automação nunca sai pelos dois provedores nem por número de outro cliente.
- Textos da interface em português do Brasil.
- Commits terminam com `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Baseline de testes em `main` (`a0064c5`): 298 runs, **11 failures + 11 errors já existentes** (ClientsControllerTest, SettingsControllerTest, CustomAutomations*, HomeControllerTest, LandingPagesControllerTest). Nenhuma task pode aumentar esse número; testes novos rodam com `bin/rails test <arquivo>`.

## Review Focus

1. **Usuário não-admin de um cliente acessando número/conversa/mídia de outro cliente por ID na URL** → 404. Testes na Task 2 (modelo) e Task 8 (controllers).
2. **Webhook repetido / eco da própria mensagem enviada** → não duplica mensagem nem conversa (contrato do Honey: lock da conexão + `provider_id` único). Teste na Task 3.
3. **Número desconectado no meio do rodízio** → checkouts vão para os outros números; se nenhum conectado, o checkout espera e não cai para Z-API. Teste na Task 5.
4. **Ligar Evolution num cliente com meses de checkouts pendentes** → nenhum checkout criado antes de `evolution_started_at` é enviado. Teste na Task 6.
5. **Cliente responde 3 mensagens seguidas com resposta automática ligada** → uma única resposta da IA; e nenhuma resposta depois que alguém da equipe escreveu. Testes na Task 9.

---

## File Structure

```
db/migrate/2026110410000*_create_whatsapp_tables.rb      Task 2
db/migrate/2026110410001*_add_whatsapp_to_clients_campaigns_checkouts.rb  Task 4/5/6/9
app/models/whatsapp/{connection,membership,contact,contact_alias,conversation,message,media,event,receipt,read,campaign_connection}.rb
app/services/whatsapp/{phone,ingest,recovery,outbound,router}.rb
app/services/whatsapp/providers/evolution.rb
app/services/openai/chat.rb
app/jobs/whatsapp/{event,sync,control,media,send,recovery,auto_reply}_job.rb
app/controllers/whatsapp/{base,webhooks,connections,conversations,messages}_controller.rb
app/views/whatsapp/conversations/index.html.erb
app/views/clients/_whatsapp_numbers.html.erb
app/views/automations/_whatsapp_numbers.html.erb, _cart_recovery_metrics.html.erb
app/javascript/whatsapp_support.js, app/assets/stylesheets/whatsapp_support.css (portados)
config/sidekiq_whatsapp.yml, config/storage.yml, Procfile, config/schedule.yml
```

---

### Task 1: Infra — S3, fila `whatsapp`, processo dedicado

**Files:**
- Modify: `Gemfile` (`gem 'aws-sdk-s3', require: false`), `config/storage.yml`, `config/environments/production.rb`, `Procfile`, `config/sidekiq.yml`
- Create: `config/sidekiq_whatsapp.yml`
- Test: `test/config/whatsapp_infra_test.rb`

**Interfaces:**
- Produces: serviço Active Storage `amazon` (bucket `ENV['WHATSAPP_S3_BUCKET']`, região `ENV['WHATSAPP_S3_REGION']`, credenciais `WHATSAPP_S3_ACCESS_KEY_ID`/`WHATSAPP_S3_SECRET_ACCESS_KEY`); `ENV['WHATSAPP_STORAGE_SERVICE']` = `amazon` em produção, ausente em dev/test (cai em `local`/`test`). Fila Sidekiq `whatsapp`.

- [ ] **Step 1: Test** `test/config/whatsapp_infra_test.rb`: `YAML.load_file('config/sidekiq_whatsapp.yml')[:queues] == ['whatsapp']`; `config/sidekiq.yml` não contém `whatsapp`; `Procfile` tem linha `whatsapp: bundle exec sidekiq -C config/sidekiq_whatsapp.yml`; `storage.yml` (ERB avaliado) tem chave `amazon` com `service: S3`.
- [ ] **Step 2:** Rodar `bin/rails test test/config/whatsapp_infra_test.rb` → FAIL.
- [ ] **Step 3:** Implementar. `sidekiq_whatsapp.yml`: `:concurrency: 5`, `:queues: [whatsapp]`. Produção continua `config.active_storage.service = :local` (outros anexos do painel não mudam); só a mídia do WhatsApp usa `WHATSAPP_STORAGE_SERVICE`. `bundle install`.
- [ ] **Step 4:** Teste → PASS.
- [ ] **Step 5:** Commit `Infra do WhatsApp: S3 para mídia e processo Sidekiq dedicado`.

### Task 2: Tabelas e modelos portados, com isolamento por cliente

**Files:**
- Create: migration `create_whatsapp_tables`; `app/models/whatsapp/*.rb` (ver estrutura); `app/services/whatsapp/phone.rb`
- Modify: `app/models/client.rb`, `app/models/user.rb`
- Test: `test/models/whatsapp/connection_test.rb`, `membership_test.rb`, `conversation_test.rb`, `media_test.rb`

**Interfaces:**
- Consumes: Task 1 (`WHATSAPP_STORAGE_SERVICE`).
- Produces:
  - Tabelas = as do Honey (`ChaseOrders/db/schema.rb`, `whatsapp_connections|contacts|contact_aliases|conversations|messages|media|events|receipts|reads|memberships`) traduzidas para Postgres (`json`→`jsonb`, `text size: :long`→`text`, sem `charset`), **sem** `whatsapp_activities`/`automation*` e **sem** as colunas `stage, agent_paused, agent_paused_at, needs_human, agent_note, agent_draft*, by_agent`. Acrescentar:
    - `whatsapp_connections.client_id` bigint **not null**, FK, index; `next_send_at` datetime.
    - `whatsapp_messages.origin` string not null default `'team'` (valores `team|automation|ai|phone`), `send_after` datetime.
    - `whatsapp_conversations.auto_reply_paused` boolean not null default false.
  - `Whatsapp::Connection belongs_to :client`; `client_id` imutável (`attr_readonly :client_id`); `instance_key` default `"mewtda-#{SecureRandom.hex(16)}"`; `Connection.visible_to(user, client:)` → `none` sem usuário; `client.whatsapp_connections` se `user.admin?`; senão `where(client_id: user.client_id)` ∩ memberships do usuário, e vazio se `client.id != user.client_id`. `Connection.administrable_by?(user) = user&.admin?`. Demais métodos (`gateway`, `connected?`, `current_qr`, `request_control!`) iguais ao Honey.
  - `Whatsapp::Membership` valida `user.client_id == connection.client_id` (erro "usuário de outro cliente").
  - `Whatsapp::Conversation`: versão do Honey sem agente/estágios; mantém `visible_to(user, client:)`, `unread_count`, `mark_read!`; `customer_wrote!` reabre se `closed`; `team_replied!` → `state: 'open', auto_reply_paused: true`.
  - `Whatsapp::Message#author_name`: `'Resposta automática'` se `origin == 'ai'`, `'Automação'` se `automation`, senão `user&.name`. `preview` cobre `image document audio video sticker`.
  - `Whatsapp::Media`: `MAX_BYTES = 16.megabytes`; `TYPES` do Honey + `video/mp4`,`video/3gpp`,`video/quicktime` → `video`, `image/gif` → `image`, `image/webp` vindo de figurinha permanece `image`; documentos aceitam também `application/msword`, `application/vnd.openxmlformats-officedocument.*`, `application/vnd.ms-excel`, `application/zip`, `text/csv` → `document`. Mensagem de erro lista os formatos.
  - `Client has_many :whatsapp_connections, class_name: 'Whatsapp::Connection', dependent: :restrict_with_exception`; `User has_many :whatsapp_memberships, class_name: 'Whatsapp::Membership', dependent: :delete_all`.

- [ ] **Step 1: Tests** (fixtures novas não; criar registros no `setup`, como `process_cart_recovery_campaigns_job_test.rb`):
  - `connection_test`: `test 'client_id não muda depois de criado'` (update para outro cliente → `reload.client_id` igual ao original); `test 'visible_to: usuário só vê números do próprio cliente com permissão'` (usuário do cliente A com membership em A1 vê `[A1]` com `client: A`, `[]` com `client: B`); `test 'visible_to: admin vê só os números do cliente em contexto'`.
  - `membership_test`: `test 'não permite usuário de outro cliente'` → `refute valid?`, erro em `:user`.
  - `conversation_test`: `test 'team_replied! pausa a resposta automática'`; `test 'customer_wrote! reabre conversa encerrada'`; `test 'contato de outro número é inválido'`.
  - `media_test`: `inspect_upload` aceita mp4 → `'video'`, rejeita 17 MB, rejeita `application/x-msdownload`.
- [ ] **Step 2:** Rodar `bin/rails test test/models/whatsapp` → FAIL.
- [ ] **Step 3:** Migration + modelos (copiar do Honey e aplicar as diferenças acima). `bin/rails db:migrate` e `RAILS_ENV=test bin/rails db:migrate`.
- [ ] **Step 4:** `bin/rails test test/models/whatsapp` → PASS; `bin/rails test` → só o baseline de falhas.
- [ ] **Step 5:** Commit `WhatsApp: tabelas e modelos portados do Honey, isolados por cliente`.

### Task 3: Provider Evolution, webhook, ingestão e jobs de base

**Files:**
- Create: `app/services/whatsapp/providers/evolution.rb`, `app/services/whatsapp/ingest.rb`, `app/services/whatsapp/recovery.rb`, `app/controllers/whatsapp/webhooks_controller.rb`, `app/jobs/whatsapp/{event,sync,control,media,send,recovery}_job.rb`
- Modify: `config/routes.rb`, `config/schedule.yml`
- Test: `test/services/whatsapp/ingest_test.rb`, `test/controllers/whatsapp/webhooks_controller_test.rb`, `test/jobs/whatsapp/send_job_test.rb`

**Interfaces:**
- Consumes: Task 2 modelos.
- Produces:
  - `Whatsapp::Providers::Evolution` = Honey com: env `EVOLUTION_API_URL`, `EVOLUTION_API_KEY`, `WHATSAPP_WEBHOOK_BASE_URL`; webhook em `"#{base}/whatsapp/webhooks/#{instance}"` com header `X-Mewtda-Webhook-Token`; `send_message` envia `video` por `sendMedia` (`mediatype: 'video'`) e `sticker` por `/message/sendSticker/:instance`.
  - `Whatsapp::Ingest#message!` = Honey, detectando `%w[image video document audio sticker]` (`stickerMessage`, `videoMessage`); `unless historical`: incoming → `conversation.customer_wrote!` e `Whatsapp::AutoReplyJob.schedule(conversation, message)` (a Task 3 cria `app/jobs/whatsapp/auto_reply_job.rb` com `self.schedule` retornando `nil`; a Task 9 implementa); mensagem de saída escrita no celular (sem `outgoing`) → `origin: 'phone'` e `conversation.team_replied!`.
  - `Whatsapp::SendJob` = Honey com: retorna sem mudar estado se `message.send_after&.future?`; `allowed?` → `team`: `Connection.visible_to(message.user, client: connection.client).exists?(connection.id)`; `automation`: `connection.client.whatsapp_evolution?` (Task 4); `ai`: `connection.client.auto_reply_ready?` (Task 9; até lá `false`).
  - `Whatsapp::Recovery.call` = Honey, mas `Message.where(state: 'queued').where('send_after IS NULL OR send_after <= ?', Time.current)`; sem nada de agente. `Whatsapp::RecoveryJob` (fila `whatsapp`) chama `Recovery.call`; cron `whatsapp_recovery` a cada minuto (`* * * * *`) em `config/schedule.yml`.
  - Todos os jobs `Whatsapp::*` com `queue_as :whatsapp`.
  - Rota fora do `scope '/crm'`: `post 'whatsapp/webhooks/:instance_key', to: 'whatsapp/webhooks#create'`.

- [ ] **Step 1: Tests**
  - `webhooks_controller_test`: token errado → 401; `instance` divergente → 422; evento válido `messages.upsert` → 202 e cria 1 `Whatsapp::Event`; mesmo payload 2× → continua 1 evento.
  - `ingest_test`: mensagem recebida cria contato+conversa+mensagem `incoming`; o mesmo `key.id` 2× → 1 mensagem; `videoMessage` → `kind 'video'`, `media_state 'pending'`; mensagem `fromMe` sem outbox → `origin 'phone'` e `conversation.auto_reply_paused == true`.
  - `send_job_test` (stub de `Providers::Evolution#send_message` com `Object#stub`): `queued` + conectado → chama provider uma vez e vira `sent`; `send_after` no futuro → não chama e continua `queued`; número desconectado → `failed`; erro do provider → `uncertain` e nunca reenvia.
- [ ] **Step 2:** Rodar os 3 arquivos → FAIL.
- [ ] **Step 3:** Implementar portando do Honey com as diferenças acima.
- [ ] **Step 4:** Testes → PASS.
- [ ] **Step 5:** Commit `WhatsApp: provider Evolution, webhook, ingestão e envio`.

### Task 4: Cliente — "Evolution Mewtda" e números (QR + permissões)

**Files:**
- Migration: `clients.whatsapp_provider` string not null default `'zapi'` (valores `zapi|evolution`).
- Create: `app/controllers/whatsapp/base_controller.rb`, `app/controllers/whatsapp/connections_controller.rb`, `app/views/clients/_whatsapp_numbers.html.erb`
- Modify: `app/models/client.rb`, `app/controllers/clients_controller.rb` (`permit :whatsapp_provider`), `app/views/clients/_form.html.erb` (aba `whatsapp`), `config/routes.rb`, JS do form do cliente (pode reaproveitar o trecho de conexões de `whatsapp_support.js` linhas ~160–330 do Honey)
- Test: `test/controllers/whatsapp/connections_controller_test.rb`, `test/models/client_test.rb`

**Interfaces:**
- Consumes: Task 2/3.
- Produces:
  - `Client#whatsapp_evolution? = whatsapp_provider == 'evolution'`; `Client#whatsapp_ready?` → evolution: algum `whatsapp_connections` conectado; zapi: `zapi_configured?`.
  - Rotas em `scope '/crm'`: `resources :clients do; namespace :whatsapp, module: 'whatsapp' do resources :connections, only: %i[index create update destroy] do member { post :connect; post :disconnect; post :sync } end end end` → `/crm/clients/:client_id/whatsapp/connections`.
  - `Whatsapp::BaseController`: Honey sem `can_access_screen?`; `require_admin!` para gestão; `current_whatsapp_client` = `Client.find(params[:client_id])` na gestão, e nas telas de conversa o cliente selecionado (`ClientScoped#current_client_id`).
  - `ConnectionsController#permitted_users(ids)` aceita só `client.users` (ids de outro cliente → 422 "Selecione somente usuários deste cliente."). `destroy` só se não houver mensagens (senão 422 "Desconecte em vez de excluir: o número tem conversas.").
  - Aba WhatsApp do form: seletor "Conexão WhatsApp" (`Z-API` / `Evolution Mewtda`); quando Evolution, lista de números (nome, telefone, estado, QR quando houver, usuários com acesso, conectar/desconectar). Campos Z-API continuam visíveis e editáveis.

- [ ] **Step 1: Tests** — `connections_controller_test`: admin cria número para cliente A → `client_id == A`; `user_ids` com usuário do cliente B → 422; não-admin → 403/redirect; `GET` index de A não lista números de B. `client_test`: `whatsapp_ready?` evolution sem número conectado → false; com um `state: 'connected', enabled: true` → true.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS + suíte no baseline.
- [ ] **Step 5:** Commit `Cliente: conexão Evolution Mewtda e números com permissão por usuário`.

### Task 5: Números responsáveis por automação e envio unificado

**Files:**
- Migration: `whatsapp_campaign_connections` (`campaign_id` FK, `connection_id` FK, `last_assigned_at` datetime, unique `[campaign_id, connection_id]`); `campaigns.evolution_started_at` datetime.
- Create: `app/models/whatsapp/campaign_connection.rb`, `app/services/whatsapp/router.rb`, `app/services/whatsapp/outbound.rb`
- Modify: `app/models/campaign.rb`, `app/jobs/customer_notification_job.rb`, `app/jobs/send_campaign_notification_job.rb`
- Test: `test/services/whatsapp/router_test.rb`, `test/services/whatsapp/outbound_test.rb`

**Interfaces:**
- Consumes: Task 3 (`Message` outbox, `SendJob`), Task 4 (`Client#whatsapp_evolution?`).
- Produces:
  - `Whatsapp::CampaignConnection` valida `connection.client_id == campaign.client_id` (erro "número de outro cliente"). `Campaign has_many :whatsapp_campaign_connections` / `:whatsapp_connections, through:`. Ao criar a primeira ligação, `campaign.update!(evolution_started_at: Time.current)` se nil.
  - `Whatsapp::Router.pick(campaign:, phone:, prefer: nil) -> Whatsapp::Connection | nil`: se `prefer` (conexão) estiver entre as da campanha e conectada → ela; senão, se já existe `Contact` com esse telefone (via `Phone.normalize`) num dos números conectados da campanha → esse número; senão o conectado com `last_assigned_at` mais antigo (nil primeiro), atualizando `last_assigned_at` sob `campaign.with_lock`. Nenhum conectado → nil.
  - `Whatsapp::Outbound.deliver(client:, campaign:, phone:, body:, prefer_connection: nil) -> Whatsapp::Outbound::Result` (`Struct(:ok, :provider, :connection, :message, :error)`):
    - `client.whatsapp_evolution?` → `Router.pick`; nil → `Result(ok: false, provider: 'evolution', error: 'sem número responsável conectado')`; senão, sob `connection.with_lock`: resolve contato/conversa (`"#{digits}@s.whatsapp.net"`, como `ConversationsController#create` do Honey), cria `Message(origin: 'automation', direction: 'outgoing', state: 'queued', kind: 'text', body:, sent_at: now, send_after: slot, client_nonce: SecureRandom.hex(16))`, onde `slot = [connection.next_send_at, now].compact.max` e `connection.next_send_at = slot + rand(8..15).seconds`; `SendJob.set(wait_until: slot).perform_later(message.id)`; atualiza `last_message_at/preview` da conversa. `ok: true`.
    - senão → `Zapi::Client.new(client).send_text(phone: format_phone(phone), message: body)`; `ok` = `response['zaapId'].present?`, `provider: 'zapi'`.
  - `CustomerNotificationJob` usa `Outbound.deliver(client: order.client, campaign: order.client.campaigns.find_by(kind: :cashback), ...)`; `SendCampaignNotificationJob` usa `campaign`; `action.mark_as_sent!/mark_as_failed!` a partir de `result.ok`/`result.error`.

- [ ] **Step 1: Tests**
  - `router_test`: dois números conectados → picks alternam A, B, A; B desconectado → A, A; nenhum conectado → nil; telefone já com contato em B → B mesmo sendo vez de A; número de outro cliente nunca é escolhido (não pode nem ser ligado — `CampaignConnection` inválido).
  - `outbound_test`: cliente zapi → chama `Zapi::Client#send_text` (stub) e não cria `Whatsapp::Message`; cliente evolution → cria 1 mensagem `queued`, `origin 'automation'`, enfileira `Whatsapp::SendJob`, não chama Z-API; duas entregas seguidas no mesmo número → `send_after` da 2ª ≥ 8 s depois da 1ª; evolution sem número → `ok false`, nada criado, Z-API não chamada.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS + suíte no baseline (ajustar testes existentes de cashback/campanha só se quebrarem pela troca para `Outbound`).
- [ ] **Step 5:** Commit `WhatsApp: números responsáveis por automação e envio unificado Z-API/Evolution`.

### Task 6: Recuperação de carrinho pela Evolution

**Files:**
- Migration: `abandoned_checkouts.whatsapp_provider` string, `whatsapp_connection_id` bigint FK null, `whatsapp_conversation_id` bigint FK null, `skip_reason` string.
- Modify: `app/jobs/process_cart_recovery_campaigns_job.rb`, `app/jobs/send_cart_recovery_notification_job.rb`, `app/models/abandoned_checkout.rb`, `app/controllers/automations_controller.rb#resend_cart_recovery`
- Test: `test/jobs/process_cart_recovery_campaigns_job_test.rb` (estender), `test/jobs/send_cart_recovery_notification_job_test.rb`

**Interfaces:**
- Consumes: Task 5 `Outbound.deliver`, `Router`.
- Produces:
  - `ProcessCartRecoveryCampaignsJob`: troca `return unless client.zapi_configured?` por `return unless client.whatsapp_ready?`; se `client.whatsapp_evolution?`, primeira mensagem só para `checkout_created_at >= campaign.evolution_started_at` (nil → nenhum).
  - `SendCartRecoveryNotificationJob#perform(abandoned_checkout_id, template, coupon_code, slot)` (mesma assinatura): slot `first` → `Outbound.deliver(...)` e grava `whatsapp_provider = result.provider`, `whatsapp_connection_id`, `whatsapp_conversation_id`; slot `second` (e reenvio) → se `checkout.whatsapp_provider` difere do provedor atual do cliente, ou `evolution` e a conexão saiu da campanha/foi excluída → não envia, grava `second_notified_at` e `skip_reason: 'canal da 1ª mensagem indisponível'`; senão `deliver(prefer_connection: checkout.whatsapp_connection)`. `first_/second_message_sent` só quando `result.ok`.
  - `AbandonedCheckout#status` acrescenta `:skipped` quando `skip_reason` presente.

- [ ] **Step 1: Tests**: evolution com checkout de antes de `evolution_started_at` → nenhum `SendCartRecoveryNotificationJob`; checkout depois → enfileira; segunda mensagem sai pela mesma conexão da primeira mesmo quando o rodízio apontaria outra; primeira por Z-API e cliente agora evolution → segunda pulada com `skip_reason`, nada enviado; cliente evolution sem número conectado → nenhum envio e checkout continua `pending`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5:** Commit `Recuperação de carrinho pela Evolution com rodízio e mesmo canal na 2ª mensagem`.

### Task 7: Telas de automação — importar números, avisos e ticket médio

**Files:**
- Create: `app/views/automations/_whatsapp_numbers.html.erb`, `app/views/automations/_cart_recovery_metrics.html.erb`, `app/services/sales/abandoned_checkout_metrics.rb`
- Modify: `app/controllers/automations_controller.rb`, `app/views/automations/{index,edit_cart_recovery,edit_cashback,edit_tracking}.html.erb`, `config/routes.rb`
- Test: `test/controllers/automations_controller_test.rb` (estender), `test/services/sales/abandoned_checkout_metrics_test.rb`

**Interfaces:**
- Consumes: Task 5 (`Campaign#whatsapp_connections`), Task 4 (`Client#whatsapp_evolution?`, `whatsapp_ready?`).
- Produces:
  - Rotas: `patch 'automations/:kind/numbers', to: 'automations#update_numbers', as: :automation_numbers` (`kind` ∈ `tracking|cashback|cart-recovery`), param `connection_ids[]`, aceitando só `@client.whatsapp_connections`.
  - Parcial `_whatsapp_numbers` (só quando `@client.whatsapp_evolution?`): checkboxes dos números do cliente com estado; aviso "Importe um número responsável — esta automação não envia sem ele." quando vazio.
  - Avisos "Integração Zapi não configurada" passam a usar `@client.whatsapp_ready?` e o texto conforme o provedor ("Nenhum número Evolution conectado" / "Integração Zapi não configurada").
  - `Sales::AbandonedCheckoutMetrics.new(client, from:, to:).call -> { count:, average_ticket:, total:, recovered_count:, recovered_total: }` sobre `abandoned_checkouts` com `checkout_created_at` no intervalo; `average_ticket = total / count` (0 se count 0), BigDecimal arredondado a 2 casas. Recuperado = `completed_at` presente.
  - Parcial `_cart_recovery_metrics` no topo de `edit_cart_recovery` e de `cart_recovery_data`, período por `params[:period]` ∈ `7|30|90` (padrão `30`), cards: Ticket médio, Checkouts abandonados, Valor abandonado, Valor recuperado (formato `number_to_currency` pt-BR).

- [ ] **Step 1: Tests**: metrics com checkouts 100, 200, 300 (um completo) → `average_ticket 200.0`, `total 600`, `recovered_total 300`; fora do período não conta; controller: `update_numbers` com id de número de outro cliente → não liga; página de cart recovery mostra "Ticket médio".
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5:** Commit `Automações: números responsáveis e ticket médio do carrinho abandonado`.

### Task 8: Tela de conversas

**Files:**
- Create: `app/controllers/whatsapp/{conversations,messages}_controller.rb`, `app/views/whatsapp/conversations/index.html.erb`, `app/javascript/whatsapp_support.js`, `app/assets/stylesheets/whatsapp_support.css`
- Modify: `config/routes.rb`, `app/views/layouts/partials/_sidebar.html.erb`, `app/views/automations/edit_cart_recovery.html.erb` (+ cashback/tracking: link "Conversas desta automação"), `package.json` build se necessário
- Test: `test/controllers/whatsapp/conversations_controller_test.rb`, `test/controllers/whatsapp/messages_controller_test.rb`

**Interfaces:**
- Consumes: Tasks 2–6.
- Produces:
  - Rotas em `scope '/crm'`: `namespace :whatsapp do resources :conversations, only: %i[index show create update] do member { post :read; patch :auto_reply } resources :messages, only: %i[index create] do member { post :retry_send; get :attachment } end end end`.
  - Controllers = Honey sem: `link_customer`, `customers`, `automation_payload`, operações de agente/`ask_agent`, `stage`, `needs_human`, `assignee`/`take`. Escopo sempre `Conversation.visible_to(current_user, client: @client)` com `@client` do `ClientScoped`. `index` aceita `campaign_id` → filtra `connection_id IN campaign.whatsapp_connections` (ainda ∩ visíveis). `MessagesController#create` cria `origin: 'team'`, `user: current_user` e chama `conversation.team_replied!`. `PATCH auto_reply` com `paused: true|false`.
  - Payload de conversa inclui `checkout: { status:, total_price:, recovery_url: }` do `AbandonedCheckout` mais recente com `whatsapp_conversation_id = conversation.id`, e `auto_reply_paused`.
  - `whatsapp_support.js`: cópia do Honey removendo todo bloco de agente (58 ocorrências de `agent`), prefixo de API vindo de `data-api-base` (`/crm/whatsapp`) no `#wa-inbox`; renderiza `video` (`<video controls>`), `sticker` (img), selo do checkout ("Recuperação 1ª/2ª enviada", "Comprou") e selo "automática" para `origin == 'ai'`; botão "Pausar/Retomar resposta automática" quando `client.auto_reply_enabled`. Upload aceita os tipos de `Media::TYPES`.
  - Menu: item "Conversas" (`fa-comments`) dentro do submenu WhatsApp, abaixo de "Automações".

- [ ] **Step 1: Tests**: usuário do cliente A sem membership no número A1 → conversa de A1 404; com membership → 200; conversa de número do cliente B por ID → 404 mesmo para admin com cliente A selecionado; `attachment` de mídia de outro cliente → 404; `POST messages` cria `queued`, `origin 'team'` e pausa auto-reply; `index?campaign_id=` só traz conversas dos números da automação.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5:** Verificar no navegador (skill `run`): conectar um número de teste pelo QR, receber mensagem com imagem e áudio, responder pelo painel.
- [ ] **Step 6:** Commit `WhatsApp: tela de conversas com mídia, permissionada por número`.

### Task 9: Resposta automática com OpenAI

**Files:**
- Migration: `clients.auto_reply_enabled` boolean default false not null, `openai_api_key` text, `openai_model` string, `auto_reply_instructions` text.
- Create: `app/services/openai/chat.rb`, `app/jobs/whatsapp/auto_reply_job.rb` (substitui o stub da Task 3)
- Modify: `app/models/client.rb` (`encrypts :openai_api_key`), `app/controllers/clients_controller.rb` (permit; chave em branco preserva a salva, como os tokens Z-API), `app/views/clients/_form.html.erb` (painel `geral`: seção "Resposta automática (OpenAI)")
- Test: `test/jobs/whatsapp/auto_reply_job_test.rb`, `test/services/openai/chat_test.rb`

**Interfaces:**
- Consumes: Task 3 (`Ingest` chama `AutoReplyJob.schedule`), Task 5/6 (mensagem/checkout ligados à conversa).
- Produces:
  - `Client#auto_reply_ready? = whatsapp_evolution? && auto_reply_enabled? && openai_api_key.present? && openai_model.present? && auto_reply_instructions.present?`.
  - `Openai::Chat.new(api_key:, model:).reply(messages:) -> String` — `POST https://api.openai.com/v1/chat/completions`, `Authorization: Bearer`, timeouts 5/30 s, sem retries, levanta `Openai::Chat::Error` em não-2xx; nunca loga corpo nem chave.
  - `Whatsapp::AutoReplyJob.schedule(conversation, message)` → nada se `!client.auto_reply_ready?`, `conversation.auto_reply_paused?` ou contato não individual; senão `set(wait: 20.seconds).perform_later(conversation.id, message.id)`.
  - `perform(conversation_id, message_id)`: retorna se existe mensagem `incoming` não histórica mais nova que `message_id` (a mais nova responde pela rajada), se pausada, ou se já existe mensagem `origin 'ai'` com `client_nonce == "ai-#{message_id}"`. Monta `system` = instruções do cliente + regra fixa "Responda em português, de forma curta, como atendente da loja. Nunca invente preços, prazos ou cupons que não estejam no contexto." + contexto do checkout ligado (itens de `line_items` com título/quantidade/preço, total, `recovery_url`, cupom enviado); histórico = últimas 20 mensagens texto (`incoming` → `user`, demais → `assistant`). Cria `Message(origin: 'ai', state: 'queued', client_nonce: "ai-#{message_id}")` e `SendJob.perform_later`. Erro da OpenAI → `Rails.logger.warn` sem reenvio.
  - Form Geral: toggle "Responder automaticamente no WhatsApp", campos "Chave da API OpenAI" (password, placeholder "deixe em branco para manter"), "Modelo" (texto livre, obrigatório quando ligado), "Instruções para a IA" (textarea). Aviso quando o cliente não está em Evolution Mewtda.

- [ ] **Step 1: Tests**: 3 mensagens seguidas → `perform` das duas primeiras não chama OpenAI e a terceira chama 1×; `auto_reply_paused` → não chama; cliente com `auto_reply_enabled false` → `schedule` não enfileira; mesma mensagem processada 2× → 1 resposta; erro da OpenAI → nenhuma mensagem criada; `Openai::Chat` (stub `Net::HTTP`) monta header Bearer e devolve `choices[0].message.content`.
- [ ] **Step 2:** FAIL. **Step 3:** Implementar. **Step 4:** PASS.
- [ ] **Step 5:** Commit `Resposta automática do WhatsApp com OpenAI, configurável por cliente`.

### Task 10: Produção

Ações externas e com custo — **confirmar com o Daniel antes de cada sub-passo marcado (⚠)**.

- [ ] **Step 1:** Suíte completa local: só o baseline de falhas.
- [ ] **Step 2 (⚠):** Criar bucket S3 privado `mewtda-painel-whatsapp` (us-east-1, bloqueio de acesso público ligado) e usuário IAM com política só para esse bucket; `heroku config:set -a mewtda-painel WHATSAPP_S3_BUCKET=… WHATSAPP_S3_REGION=us-east-1 WHATSAPP_S3_ACCESS_KEY_ID=… WHATSAPP_S3_SECRET_ACCESS_KEY=… WHATSAPP_STORAGE_SERVICE=amazon WHATSAPP_WEBHOOK_BASE_URL=https://www.mewtda.com.br`.
- [ ] **Step 3 (⚠):** Antes de ligar workers, inspecionar a fila Sidekiq de produção (`Sidekiq::Queue.new('default').size` e classes) e decidir com o Daniel se limpa jobs velhos de envio.
- [ ] **Step 4 (⚠):** Deploy do código (mesmo fluxo dos deploys anteriores do `mewtda-painel`); release roda as migrations.
- [ ] **Step 5 (⚠):** `heroku ps:scale worker=1 whatsapp=1 -a mewtda-painel`.
- [ ] **Step 6:** Verificar: `heroku ps` com web/worker/whatsapp `up`; `POST /whatsapp/webhooks/x` sem token → 401; no painel, cliente de teste em "Evolution Mewtda", criar número, QR aparece, conectar, mandar/receber texto e imagem.
- [ ] **Step 7:** Atualizar `README.md` do painel com as variáveis novas e o processo `whatsapp`.
