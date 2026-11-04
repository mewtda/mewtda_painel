# Recuperação de carrinho via Evolution (WhatsApp) — design

Data: 2026-11-04

## Intenção

Hoje a recuperação de carrinho do CRM (`/crm/automations/cart-recovery`) manda mensagem por **um número
Z-API por cliente**, e ninguém vê nem responde a conversa que nasce dali. A ideia é passar o envio para a
**Evolution API da Mewtda** (`mewtda-evolution`, já no ar e ligada ao painel por `EVOLUTION_API_URL` /
`EVOLUTION_API_KEY`), permitir **vários números por cliente**, dividir os checkouts entre eles e dar à equipe
uma **tela de conversas** dentro da automação para atender quem respondeu — como o atendimento WhatsApp do
Honey (`ChaseOrders`), que já faz isso para a Chase.

Esta é a primeira funcionalidade em cima da Evolution; os números conectados devem servir depois a outras
automações (por isso o número pertence ao cliente, não à automação).

## Objetivos

1. Na edição do cliente (`/crm/clients/:id/edit`, aba WhatsApp), escolher que o cliente usa a conexão
   **Evolution Mewtda**, criar números, escanear o QR, ver o status de cada um e definir **quais usuários
   têm acesso a cada número**.
2. Na recuperação de carrinho (`/crm/automations`), **importar números conectados** do cliente para a
   automação. Valem as regras de envio já existentes: atraso em minutos após o abandono, mensagem, cupom e
   segunda mensagem opcional (atraso em horas, mensagem e cupom próprios).
3. Com mais de um número na automação, **dividir os checkouts entre eles**.
4. **Tela de conversas** dentro da automação: uma aba por número que o usuário pode ver; lista de conversas
   com o status do checkout; chat para ler e responder.
5. **Ticket médio do carrinho abandonado** na tela da automação.
6. **Estrutura pronta de resposta automática com OpenAI**, desligada por padrão e configurada na aba
   **Geral** da edição do cliente (`/crm/clients/:id/edit#geral`). Quando ligada, mensagens recebidas nos
   números Evolution do cliente são respondidas automaticamente pela OpenAI.

## Não-objetivos

- **Nada do agente de IA do Honey**: sem sugestão de resposta para o atendente, modo conversa, regras/gaps/
  capabilities/ferramentas (consulta de estoque, criar pedido). A única IA é a resposta automática simples
  do objetivo 6.
- Não remover a Z-API: o cliente que não escolher Evolution continua exatamente como hoje.
- Não mexer na API Oficial (Cloud API da Meta) que já está guardada no cliente.
- Sem listas de transmissão nem tipos novos de automação; os fluxos existentes só trocam de canal.

## Anti-objetivos (seria fracasso mesmo funcionando)

- Um usuário ver conversas de um número a que não tem acesso.
- O mesmo checkout receber a mensagem duas vezes (por dois números, ou por Z-API e Evolution).
- Perder mensagens recebidas porque o worker caiu ou o Redis foi perdido.
- Misturar números/conversas entre clientes.

## Restrições e contexto

- `mewtda-painel`: Rails, Sidekiq + `sidekiq-cron` (`config/schedule.yml`), ActionCable em Redis, Bootstrap/
  Stimulus, layout do CRM em `/crm`. Usuário `belongs_to :client`; `admin?` é `profile_id == 1`.
- Checkouts abandonados chegam pelo `AbandonedCheckoutsSyncJob` em `AbandonedCheckout`
  (`total_price`, `phone`, `recovery_url`, `completed_at`, `first_/second_notified_at`…).
- A automação é um `Campaign` com `kind: :cart_recovery` (um por cliente), processada por
  `ProcessCartRecoveryCampaignsJob` → `SendCartRecoveryNotificationJob` (hoje fixo em `Zapi::Client`).
- Evolution API **2.3.7** (mesmo contrato do Honey). Uma instância Evolution = um número.
- Deploy do painel é produção direta; tudo novo precisa conviver com o fluxo Z-API em funcionamento.

## Decisões tomadas pelo Daniel

- A conexão é escolhida **no cliente** ("Evolution Mewtda"); os números são **importados** na automação.
- Vários números por automação; **os checkouts são divididos entre eles**.
- **Permissão por número por usuário**; o usuário entra na tela e conversa com os clientes por ela.
- Referência de comportamento e de código: o atendimento WhatsApp do Honey em `ChaseOrders`.
- Sem o agente de IA do Honey; mas **deixar pronta a resposta automática**, com **OpenAI**, configurada na
  aba Geral do cliente.

## Como (direção)

**Portar do Honey a base de WhatsApp**, sem a parte de IA. Em `ChaseOrders`:
`app/models/whatsapp/{connection,membership,contact,conversation,message,event,receipt,read,media}.rb`,
`app/services/whatsapp/{providers/evolution,ingest,phone,recovery}.rb`,
`app/controllers/whatsapp/{connections,conversations,messages,webhooks,health}_controller.rb`,
`app/jobs/whatsapp/{control,event,media,send,sync}_job.rb`, a view `whatsapp/conversations/index` e
`app/javascript/whatsapp_support.js` + CSS. Ficam de fora `agent*`, `automation*`, `learned_template`,
`activity`, `contact_alias` (se só servir à IA) e os jobs `agent_job`/`resume_agent_job`.

Adaptações:

- `Whatsapp::Connection` passa a **pertencer a um `Client`**; `instance_key` com prefixo `mewtda-`.
  `visible_to(user)`: admin vê todas as do cliente em contexto; não-admin vê só as em que tem `Membership`
  **e** do seu próprio `client`.
- `Client` ganha a escolha do provedor de WhatsApp para automações (Z-API | Evolution Mewtda).
- A automação (`Campaign` cart_recovery) ganha a lista de conexões importadas (tabela de ligação
  campanha ↔ conexão).
- Webhook da Evolution aponta para o painel (`https://www.mewtda.com.br/...`) por instância, com token, como
  no Honey.
- `SendCartRecoveryNotificationJob` escolhe o provedor pelo cliente: Z-API como hoje, ou cria uma
  `Whatsapp::Message` na conversa do número escolhido e deixa o `SendJob` enviar. O `AbandonedCheckout`
  passa a guardar por qual conexão saiu.
- **Divisão entre números (decisão do Claude):** rodízio entre as conexões **conectadas** da automação; a
  segunda mensagem e qualquer reenvio saem **pelo mesmo número** da primeira. Se o telefone já tem conversa
  com um dos números da automação, usa esse número. Número desconectado sai do rodízio; se nenhum estiver
  conectado, o checkout espera (não cai para a Z-API).
- **Tela de conversas:** rota dentro de `/crm/automations/cart-recovery/...`, abas por número visível ao
  usuário, mesma UX do Honey. Mostra **todas** as conversas do número (é um WhatsApp real), com selo do
  checkout (enviado 1ª / 2ª, respondeu, comprou) quando a conversa veio de uma recuperação.
- **Ticket médio (decisão do Claude):** média de `total_price` dos checkouts abandonados do cliente no
  período escolhido na tela (padrão: últimos 30 dias), mostrado junto com quantidade de checkouts, valor
  total abandonado e valor recuperado (`completed_at` preenchido).

- **Resposta automática (OpenAI)** — campos na aba Geral do cliente: ligar/desligar (padrão desligado),
  chave da API OpenAI (criptografada com `encrypts`, como os outros tokens), modelo e instruções (prompt
  do negócio: tom, políticas, o que pode prometer). Decisões do Claude:
  - Responde só em números Evolution do cliente e só a mensagens **recebidas** de contatos (nunca grupos).
  - Contexto enviado: instruções do cliente + últimas mensagens da conversa + dados do checkout ligado à
    conversa, se houver (itens, valor, link de recuperação, cupom enviado).
  - **Pausa quando um humano assume**: se alguém da equipe enviar mensagem pela tela, a resposta automática
    para naquela conversa (com botão para religar na conversa).
  - Espera alguns segundos e junta mensagens seguidas do cliente antes de responder (uma resposta por
    rajada); falha da OpenAI só registra o erro, não reenvia em loop.
  - Mensagens geradas pela IA ficam marcadas na conversa (selo "automática").
  - Chamada à OpenAI isolada num serviço (`app/services/openai/…`) para trocar de provedor depois.

- **Escopo do provedor (decisão do Daniel):** "Evolution Mewtda" no cliente vale para **tudo**: com ela
  ligada, todo envio de WhatsApp do cliente sai pela Evolution — recuperação de carrinho, cashback,
  rastreio (`CustomerNotificationJob`), campanhas (`SendCampaignNotificationJob`) e reenvios manuais. Hoje
  esses fluxos chamam `Zapi::Client` direto e checam `zapi_configured?` (jobs acima, `Campaign`, views de
  automações/campanhas e o form do cliente). O builder cria uma camada única de envio (ex.:
  `Whatsapp::Sender.for(client)`) com Z-API e Evolution por trás, e troca todas essas chamadas por ela;
  "WhatsApp configurado" passa a significar Z-API **ou** Evolution com número conectado. Cliente sem
  Evolution continua igual.
- **Qual número envia cada automação (decisão do Daniel):** dentro de **cada** automação/campanha você
  importa o(s) número(s) **responsável(is)** por ela, como na recuperação de carrinho; com mais de um, divide
  em rodízio. *Decisão do Claude:* automação sem número responsável não envia (aparece um aviso "importe um
  número responsável" na tela dela); não cai para outro número nem para a Z-API. As conversas geradas por
  qualquer automação aparecem na tela de conversas do número, acessível pela aba dentro da automação e por
  uma entrada própria no menu do CRM ("Conversas").
- **Checkouts antigos (decisão do Claude):** pela Evolution só entram checkouts criados **depois** que o
  primeiro número foi importado na automação (guardar esse marco), para não disparar meses de checkouts
  acumulados num número recém-pareado. Envio por número com intervalo mínimo entre mensagens
  (alguns segundos, com variação) para reduzir risco de bloqueio.
- **Troca de provedor no meio (decisão do Claude):** cada `AbandonedCheckout` guarda por qual provedor/conexão
  saiu a 1ª mensagem; a 2ª e o reenvio manual saem pelo mesmo caminho. Se esse caminho não existir mais
  (Z-API removida, número excluído), a 2ª é pulada e o status mostra o motivo. Nunca enviar pelos dois.
- **Agendamento:** os jobs recorrentes novos (processar recuperação, recuperação de eventos/envios do
  WhatsApp) entram no `config/schedule.yml` (sidekiq-cron).
- **Evolution (`mewtda-evolution`):** já salva mensagens no próprio banco
  (`DATABASE_SAVE_DATA_NEW_MESSAGE=true`, histórico e contatos ligados) e tem `WEBHOOK_GLOBAL_ENABLED=false`;
  o webhook é configurado por instância pelo painel, como no Honey. `/chat/findMessages` e
  `getBase64FromMediaMessage` funcionam.

- **Mídia (decisão do Daniel): tudo aparece no chat** — imagens, áudios (com player), vídeos, documentos,
  figurinhas — e a equipe pode enviar anexos, como no Honey (`Whatsapp::Media`, `MediaJob`). Produção hoje
  usa Active Storage em disco (`:local`), que o Heroku apaga a cada deploy/reinício; o builder configura
  **Active Storage em S3** (gem `aws-sdk-s3`, serviço `amazon` no `storage.yml`, bucket privado novo na conta
  AWS que já serve o SES, credenciais só para esse bucket) antes de portar a mídia. URLs servidas pelo painel
  com checagem de permissão por número, nunca links públicos permanentes.
- **Processos (decisão do Claude, com custo):** hoje o `worker` do `mewtda-painel` está com **0 dynos** em
  produção, então nada do Sidekiq roda lá. Ligar 1 `worker` (Basic, ~US$7/mês) e criar um processo
  `whatsapp` dedicado (`bundle exec sidekiq -C config/sidekiq_whatsapp.yml`, fila `whatsapp`, Basic,
  ~US$7/mês), como no Honey, para webhooks, envios, mídia e OpenAI não travarem cashback/recuperação.
  Ligar o worker atual faz rodar de uma vez o que estiver parado na fila e os crons do `schedule.yml` — o
  builder confere a fila antes (e com o Daniel) para não disparar mensagens velhas.

## Deixado para quem construir

- Nome exato de tabelas/colunas, rotas e organização dos controllers no namespace `/crm`.
- Tempo real na tela de conversas: o que o Honey faz hoje (polling ou cable) pode ser mantido.
- Testes no padrão do projeto (`test/`, Minitest).
