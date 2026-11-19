# Campanhas com WhatsApp (API Oficial) e várias mensagens — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Campanhas com abas E-mail e WhatsApp, várias mensagens com data/hora cada, vários segmentos, e modelos de WhatsApp criados no painel e aprovados pela Meta, enviando pela Cloud API.

**Architecture:** `Campaign` vira o contêiner (nome, segmentos, canais ativos, status/contagens agregados). Cada envio é uma `CampaignMessage` (canal, modelo, `send_at`) com seu próprio ciclo de despacho; o `DispatchJob` passa a operar por mensagem e escolhe o remetente pelo canal. WhatsApp usa um cliente HTTP fino da Graph API (`Whatsapp::Cloud::Api`) com credenciais do `Client`.

**Tech Stack:** Rails 7.2, Postgres, Sidekiq + sidekiq-cron (`config/schedule.yml`), HTTParty, Minitest (`Object#stub`), JS vanilla em `app/javascript`.

**Spec:** `docs/superpowers/specs/2026-11-19-campanhas-whatsapp-design.md`

## Global Constraints

- Graph API: `https://graph.facebook.com/v26.0` (mesma versão de `Meta::MonthlyCostFetcher::GRAPH_API_VERSION`).
- Modelos: categoria `MARKETING`, idioma `pt_BR`, nome `^[a-z0-9_]{1,512}$`, `{{1}}` = primeiro nome ou `cliente`; no máximo um botão URL e um rodapé.
- Erros Meta: `130429` → pausa 1 min e continua; `131049`, `131050`, `131047` → recipient `blocked`; demais → `failed` com `error.message` (máx. 250 chars).
- Token do WhatsApp nunca em log, erro, JSON ou view.
- Testes nunca chamam a rede: todo HTTP passa por `Whatsapp::Cloud::Api` dublado com `stub`.
- Banco de teste local: `RAILS_ENV=test` → `postgres://localhost/mewtda_painel_test`. Nunca rodar `db:migrate` sem `RAILS_ENV=test` (o `.env` de desenvolvimento aponta para produção).
- Textos de UI em português, no tom das telas atuais; classes CSS seguindo `ec-*`/`crm-*`/`cform-*`.
- Sem `Co-Authored-By` extra além do padrão do harness; commits pequenos por task; branch `feature/campanhas-whatsapp`.

## Review Focus

- Pessoa em dois segmentos escolhidos → recebe cada mensagem uma vez (teste na Task 5).
- Telefones `(16) 99237-5432`, `16992375432` e `+5516992375432` do mesmo cliente → um único envio (Task 5).
- Job reexecutado depois de enviar metade do lote → não reenvia quem já está `sent` (Task 6).
- Modelo de WhatsApp deixa de estar aprovado ou cliente sem API configurada na hora do envio → mensagem pausa com nota, sem `failed` em massa (Task 6).
- Campanha antiga (só e-mail, já enviada) depois da migração → lista, detalhes, planilha e desempenho mostram os mesmos números de antes (Task 4).

---

### Task 1: Cliente da Cloud API

**Files:**
- Create: `app/services/whatsapp/cloud/api.rb`
- Test: `test/services/whatsapp/cloud/api_test.rb`

**Interfaces:**
- Produces: `Whatsapp::Cloud::Api.new(client)`; `#configured? -> Boolean`;
  `#send_template(to:, name:, language:, body_params: []) -> String` (wamid);
  `#create_template(payload Hash) -> Hash` (`{'id','status','category'}`);
  `#templates -> Array<Hash>` (`name,status,id,rejected_reason,category`, segue paginação);
  `#delete_template(name:) -> true`.
  Erros: `Whatsapp::Cloud::Api::Error` com `#code` (Integer) e `#message` sem token; subclasses
  `RateLimited` (130429), `Blocked` (131049/131050/131047), `NotConfigured`.
- `to` aceita qualquer formato; envia só dígitos (`Whatsapp::Phone.normalize(to).delete_prefix('+')`).

- [ ] **Step 1: Testes** — dublando `HTTParty.post/get/delete` com `stub`:
  - `send_template` monta `{messaging_product:'whatsapp', to:'5516992375432', type:'template', template:{name:'black_1', language:{code:'pt_BR'}, components:[{type:'body', parameters:[{type:'text', text:'Ana'}]}]}}`, header `Authorization: Bearer <token>`, URL `.../v26.0/<phone_id>/messages`, retorna o `messages[0].id`.
  - resposta `{"error":{"code":130429,...}}` levanta `RateLimited`; `131050` levanta `Blocked`; `100` levanta `Error` com `code == 100`; `error.message` não contém o token.
  - `templates` segue `paging.next` até acabar.
  - `configured?` falso sem phone_id/waba/token.
- [ ] **Step 2:** `bin/rails test test/services/whatsapp/cloud/api_test.rb` → falha (constante não existe).
- [ ] **Step 3:** Implementar com `HTTParty`, `timeout: 15`, sem logar corpo.
- [ ] **Step 4:** Rodar o teste → PASS.
- [ ] **Step 5:** Commit `WhatsApp: cliente da API Oficial (Cloud API)`.

### Task 2: Modelos de WhatsApp (dados + sincronização)

**Files:**
- Create: `db/migrate/20261119120000_create_whatsapp_templates.rb`, `app/models/whatsapp_template.rb`,
  `app/services/whatsapp/cloud/template_sync.rb`, `app/jobs/whatsapp/template_sync_job.rb`
- Modify: `app/models/client.rb` (`has_many :whatsapp_templates, dependent: :destroy`), `config/schedule.yml`
- Test: `test/models/whatsapp_template_test.rb`, `test/services/whatsapp/cloud/template_sync_test.rb`

**Interfaces:**
- Consumes: Task 1.
- Produces: tabela `whatsapp_templates` (colunas do spec; `status` default `draft`; único `[client_id, name]`).
  `WhatsappTemplate::STATUSES = %w[draft pending approved rejected paused disabled]`;
  `#editable?` (draft/rejected); `#approved?`; `#submit! -> true|false` (chama `create_template`, grava `meta_id`, `status` da Meta em minúsculas, `synced_at`; em erro guarda `errors[:base]` com a mensagem da Meta);
  `#meta_payload -> Hash`; `#preview_body(first_name = 'Maria') -> String`;
  `.approved`; `name` gerado de `label` (`parameterize(separator: '_')` + sufixo se colidir) quando vazio.
  `Whatsapp::Cloud::TemplateSync.new(client).call` atualiza status/motivo dos modelos do cliente pelo `name`.
  `Whatsapp::TemplateSyncJob` roda para clientes com modelos `pending`; cron `*/10 * * * *`.
- Validações: `label` presente ≤ 120; `body` presente ≤ 1024; `footer` ≤ 60; `button_text` ≤ 25 e `button_url` http(s) quando presente; `body` só pode usar `{{1}}`; `body_example` obrigatório se `body` tem `{{1}}`.

- [ ] **Step 1: Testes** — `meta_payload` para corpo com `{{1}}`, rodapé e botão:
  `{name:, category:'MARKETING', language:'pt_BR', components:[{type:'BODY', text:, example:{body_text:[['Maria']]}}, {type:'FOOTER', text:}, {type:'BUTTONS', buttons:[{type:'URL', text:, url:}]}]}`;
  corpo com `{{2}}` é inválido; `submit!` grava `pending` e `meta_id` com API dublada; sync muda `pending`→`approved` e `rejected` com `rejected_reason`.
- [ ] **Step 2:** `RAILS_ENV=test bin/rails db:migrate` e rodar os testes → falham.
- [ ] **Step 3:** Implementar migração, modelo, sync, job e entrada no `schedule.yml`.
- [ ] **Step 4:** Testes → PASS.
- [ ] **Step 5:** Commit `WhatsApp: modelos de mensagem com aprovação da Meta`.

### Task 3: Tela Comunicação > WhatsApp

**Files:**
- Create: `app/controllers/whatsapp_templates_controller.rb`, `app/views/whatsapp_templates/{index,new,edit,_form}.html.erb`, `app/javascript/whatsapp_templates.js` (prévia ao vivo em balão)
- Modify: `config/routes.rb` (dentro do mesmo escopo de `email_templates`: `resources :whatsapp_templates, path: 'modelos-whatsapp', except: [:show] do member { post :submit; post :duplicate } end`), `app/views/layouts/partials/_sidebar.html.erb` (item "WhatsApp" depois de "E-mail", ícone `fa-brands fa-whatsapp`, ativo em `whatsapp_templates_path`)
- Test: `test/controllers/whatsapp_templates_controller_test.rb`

**Interfaces:**
- Consumes: Task 2.
- Comportamento: index lista label, status (tag), prévia curta, ações; aviso no topo se `!Whatsapp::Cloud::Api.new(client).configured?` com link para Configurações. `index` chama `TemplateSync` quando há `pending` (rescue de erro da API → flash discreto). `update` só se `editable?`. `submit` envia para a Meta. `duplicate` cria rascunho `"<label> (cópia)"`. `destroy` apaga na Meta se `meta_id` presente.

- [ ] **Step 1: Testes** — lista só modelos do cliente atual; criar redireciona ao index; editar aprovado é recusado; `submit` com API dublada deixa `pending`; outro cliente recebe 404/redirect.
- [ ] **Step 2:** Rodar → falha.
- [ ] **Step 3:** Implementar controller, views (padrão de `email_templates`), JS de prévia, rota e menu.
- [ ] **Step 4:** Testes → PASS.
- [ ] **Step 5:** Commit `Comunicação > WhatsApp: criar e enviar modelos para aprovação`.

### Task 4: Campanha com segmentos e mensagens (dados + migração)

**Files:**
- Create: `db/migrate/20261119130000_create_campaign_messages.rb` (tabelas + colunas + migração de dados com SQL), `app/models/campaign_message.rb`, `app/models/campaign_segment.rb`
- Modify: `app/models/campaign.rb`, `app/models/campaign_recipient.rb`
- Test: `test/models/campaign_message_test.rb`, `test/models/campaign_test.rb`, `test/migrations/create_campaign_messages_test.rb`

**Interfaces:**
- Produces:
  - `campaign_segments(campaign_id, segment_id)` único; `Campaign has_many :segments, through:`.
  - `campaigns.email_enabled` (default true), `campaigns.whatsapp_enabled` (default false).
  - `campaign_messages` (colunas do spec) e `CampaignMessage::STATUSES = %w[draft scheduled sending paused sent cancelled]`, `RUNNABLE = %w[scheduled sending paused]`, `CHANNELS = %w[email whatsapp]`, `belongs_to :email_template, optional`, `belongs_to :whatsapp_template, optional`, `has_many :recipients, class_name: 'CampaignRecipient'`, `#template_name`, `#first_send_at(from)`, `#recount!`.
  - `campaign_recipients.campaign_message_id`, `channel` (default `email`), `phone`, `provider_message_id`; `email` nulo permitido; índices únicos parciais `[campaign_message_id, email] WHERE channel='email'` e `[campaign_message_id, phone] WHERE channel='whatsapp'`; validação: email presente se e-mail, phone se WhatsApp.
  - `Campaign#messages` (ordenadas por `send_at NULLS FIRST, position`), `#active_messages` (canais ligados), `#refresh_from_messages!` (status agregado conforme spec; soma `recipients_count/sent/failed/blocked`; `started_at` = menor; `finished_at` quando todas terminaram; `next_run_at` = menor das executáveis), `#missing_steps` (nome; ao menos um segmento; ao menos um canal ligado; cada canal ligado com ≥1 mensagem; toda mensagem com modelo; modelo de WhatsApp aprovado; data no futuro para mensagens com data), `#timing_summary` (ex.: `"3 mensagens · 27/11 10:00 a 29/11 18:00"`).
  - Campos antigos (`email_template_id`, `segment_id`, `send_mode`, `scheduled_at`, janela) ficam no banco e deixam de ser usados no código.
- Migração de dados: para cada campanha, `campaign_segments` a partir de `segment_id`; uma `campaign_messages` `email` com `email_template_id`, `send_at = COALESCE(scheduled_at, published_at)`, mesmo `status`, `next_run_at`, `audience_frozen_at`, contagens, `started_at`, `finished_at`; `campaign_recipients.campaign_message_id` dessa mensagem. Campanhas em modo `window` ainda executáveis: manter `next_run_at` atual (continuam a partir dele).

- [ ] **Step 1: Testes** — status agregado (uma `sending` → campanha `sending`; todas `sent` → `sent`; só `scheduled` futuras → `scheduled`); `missing_steps` para WhatsApp com modelo não aprovado; teste da migração: monta via SQL uma campanha antiga enviada com 2 destinatários, roda `up` e confere mensagem, segmento e destinatários ligados, contagens iguais.
- [ ] **Step 2:** Migrar o banco de teste e rodar → falha.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Testes novos e os antigos de `campaign_test.rb` atualizados → PASS.
- [ ] **Step 5:** Commit `Campanhas: mensagens por canal e vários segmentos`.

### Task 5: Público por canal e por vários segmentos

**Files:**
- Modify: `app/services/campaigns/audience.rb`
- Test: `test/services/campaigns/audience_test.rb`

**Interfaces:**
- Produces: `Campaigns::Audience.new(client, segments, channel: 'email'|'whatsapp')`;
  `#recipients_scope` (perfis da união, sem duplicar perfil); `#call -> Result` (e-mail: campos atuais; WhatsApp: `total, without_phone, recipients`);
  `#each_recipient { |profile, address| }` — para WhatsApp `address` é `Whatsapp::Phone.normalize(profile.phone)` e números repetidos são pulados.
- Regras de e-mail inalteradas (lista de recusa, `email_marketing_state`).

- [ ] **Step 1: Testes** — perfil em dois segmentos conta 1; três formatos do mesmo telefone geram 1 envio; perfil sem telefone entra em `without_phone`; e-mail na lista de recusa continua fora.
- [ ] **Step 2:** Rodar → falha.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** Testes → PASS.
- [ ] **Step 5:** Commit `Campanhas: público por canal e vários segmentos`.

### Task 6: Envio por mensagem (e-mail e WhatsApp)

**Files:**
- Modify: `app/jobs/campaigns/dispatch_job.rb`, `app/jobs/campaigns/tick_job.rb`, `app/services/billing/usage.rb`
- Create: `app/services/campaigns/senders/email.rb`, `app/services/campaigns/senders/whatsapp.rb`
- Test: `test/jobs/campaigns/dispatch_job_test.rb` (adaptar), `test/jobs/campaigns/whatsapp_dispatch_test.rb`, `test/jobs/campaigns/tick_job_test.rb`

**Interfaces:**
- Consumes: Tasks 1, 4, 5.
- Produces: `Campaigns::DispatchJob.perform_later(campaign_message_id)` (mesmo lease/`claim` atual, agora em `campaign_messages`); ao final chama `campaign.refresh_from_messages!`.
  `TickJob` acorda `CampaignMessage.where(status: RUNNABLE).where(next_run_at: ..now)`.
  Senders: `#deliver(recipient) -> :sent | :failed | :blocked | [:pause, Time]`, `#ready? -> String|nil` (motivo para pausar). E-mail = lógica atual extraída sem mudar comportamento. WhatsApp: `send_template(to: recipient.phone, name: template.name, language: 'pt_BR', body_params: template has {{1}} ? [first_name] : [])`, grava `provider_message_id`; `ready?` retorna motivo se API não configurada ou modelo não `approved`.
  `Billing::Usage#count('whatsapp', range)` passa a somar `CampaignRecipient` com `channel: 'whatsapp', status: 'sent', sent_at: range` dos campos do cliente.
  Limite diário de WhatsApp → pausa até `resume_at` (8h do dia seguinte).

- [ ] **Step 1: Testes** — todos os testes atuais do dispatch adaptados para mensagem de e-mail continuam verdes; WhatsApp: envia para 3 perfis com `{{1}}` = primeiro nome; `RateLimited` pausa e reagenda em 1 min sem marcar falha; `Blocked` → `blocked`; reexecução não reenvia `sent`; modelo `paused` → mensagem `paused` com `next_run_at` +1h e nenhuma chamada; limite diário 2 com 3 pessoas → 2 enviados e pausa para amanhã 8h; Tick acorda só mensagens vencidas.
- [ ] **Step 2:** Rodar → falha.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** `bin/rails test test/jobs test/services` → PASS.
- [ ] **Step 5:** Commit `Campanhas: envio por mensagem com WhatsApp pela API Oficial`.

### Task 7: Editor da campanha (abas, mensagens, teste, revisão)

**Files:**
- Modify: `app/controllers/campaigns_controller.rb`, `app/views/campaigns/edit.html.erb`, `app/javascript/campaigns.js`, CSS da campanha (arquivo onde estão as classes `ec-*`)
- Create: `app/views/campaigns/_message.html.erb` (linha de mensagem), `app/views/campaigns/_whatsapp_preview.html.erb`
- Test: `test/controllers/campaigns_controller_test.rb` (adaptar e ampliar)

**Interfaces:**
- Consumes: Tasks 2, 4, 5, 6.
- Params: `campaign[name]`, `campaign[segment_ids][]`, `campaign[email_enabled]`, `campaign[whatsapp_enabled]`,
  `campaign[messages_attributes][i][id|channel|email_template_id|whatsapp_template_id|send_now|send_on|send_time|_destroy]` (`accepts_nested_attributes_for :messages, allow_destroy: true`; `send_now == '1'` → `send_at = nil`).
- `update` (JSON, autosave atual) devolve `summary_json` com `steps`, `missing`, `ready`, `channels: { email: {enabled, recipients, cost, ...}, whatsapp: {enabled, configured, recipients, without_phone} }`, `messages: [{id, channel, template, when}]`.
- Nova ação `send_test_whatsapp` (`post :send_test_whatsapp` no member): `phone` + `whatsapp_template_id` → envia o modelo com nome "Maria"; mesmo `rate_limit` do teste de e-mail.
- `schedule`: valida `missing_steps`, público > 0 por canal ligado, e-mail exige domínio verificado só se e-mail ligado; marca cada mensagem ativa `scheduled` com `next_run_at = send_at || agora`; mensagens de canal desligado ficam `cancelled`; chama `refresh_from_messages!`; enfileira `DispatchJob` das que já venceram.
- UI: passo 1 nome; passo 2 segmentos (multi-select com `data-custom-select`); passo 3 abas E-mail/WhatsApp com chave, lista de mensagens (modelo + "Assim que confirmar" ou data/hora), botão "Adicionar mensagem"; lateral com resumo por canal, prévia (iframe do e-mail ou balão do WhatsApp da mensagem selecionada) e testes. Aba WhatsApp desabilitada com explicação se a API não estiver configurada; sem modelos aprovados mostra link para "Comunicação > WhatsApp".
- O consentimento de marketing atual (e-mail) continua no diálogo de revisão.

- [ ] **Step 1: Testes** — salvar com dois segmentos e duas mensagens (uma WhatsApp, uma e-mail) persiste e devolve `ready: true`; WhatsApp ligado com modelo pendente → `missing` contém "aprovado"; `schedule` agenda as duas mensagens com `next_run_at` certos e enfileira só a de "agora"; teste de WhatsApp chama a API dublada com o telefone informado; canal desligado no `schedule` → mensagens `cancelled`.
- [ ] **Step 2:** Rodar → falha.
- [ ] **Step 3:** Implementar controller, views, JS e CSS.
- [ ] **Step 4:** Testes → PASS; abrir `bin/rails s` com o banco local de dev **não** é possível (aponta para produção): validar visualmente só no review app/produção após merge.
- [ ] **Step 5:** Commit `Campanhas: editor com abas de E-mail e WhatsApp e várias mensagens`.

### Task 8: Lista, detalhes, planilha e desempenho

**Files:**
- Modify: `app/views/campaigns/index.html.erb`, `app/views/campaigns/_details.html.erb`, `app/services/spreadsheets/campaign_recipients.rb`, `app/services/campaigns/performance.rb`, `app/controllers/campaigns_controller.rb#index` (filtro `canal` por mensagens), `app/helpers/campaigns_helper.rb`
- Test: `test/controllers/campaigns_controller_test.rb`, `test/controllers/campaign_performance_controller_test.rb`

**Interfaces:**
- Consumes: Task 4.
- Lista: coluna "Canal de envio" com tags dos canais ligados; "Para quem" com nomes dos segmentos; "Envio" com `timing_summary` e progresso agregado. Detalhes: bloco por mensagem (canal, modelo, data, enviados/falhas/bloqueios, baixar lista). Planilha: aceita `message_id` e inclui telefone. Desempenho: soma campanha; investimento = só e-mail enviados.

- [ ] **Step 1: Testes** — filtro `canal=whatsapp` mostra só campanhas com mensagem de WhatsApp; detalhes de campanha migrada mostram os mesmos números; planilha de WhatsApp tem coluna de telefone.
- [ ] **Step 2:** Rodar → falha.
- [ ] **Step 3:** Implementar.
- [ ] **Step 4:** `bin/rails test` completo → PASS.
- [ ] **Step 5:** Commit `Campanhas: lista, detalhes e desempenho por mensagem`.

### Task 9: Entrega

- [ ] **Step 1:** `bin/rails test` completo e `bundle exec rubocop` nos arquivos alterados → verdes.
- [ ] **Step 2:** Antes do merge, consultar produção (somente leitura): quantas campanhas executáveis em modo `window` existem; reportar ao Daniel.
- [ ] **Step 3:** `git push -u origin feature/campanhas-whatsapp` e abrir PR com resumo, riscos (migração de dados) e roteiro de teste manual em produção.
- [ ] **Step 4:** Após o merge e deploy, validar em produção: criar modelo na OneWay, enviar para aprovação, mandar teste de WhatsApp para o número do Daniel.
