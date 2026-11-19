# Campanhas com WhatsApp (API Oficial) e várias mensagens — desenho

Data: 2026-11-19 · Primeiro cliente: OneWay (cliente 34)

## Por quê

A OneWay quer disparar mensagens de marketing (começando pela campanha da Black) pelo número
+55 31 99013-1953, conectado na API Oficial do WhatsApp (Cloud API), a partir do mewtda-painel.
Hoje as campanhas só enviam e-mail e o WhatsApp automático só sai pela Evolution (QR Code).
A loja quer montar, numa mesma campanha, uma sequência de mensagens de WhatsApp e de e-mail,
cada uma com data e hora, sempre escolhendo os segmentos que recebem.

## Objetivos

- **Comunicação > WhatsApp**: a loja cria vários modelos de mensagem no painel; o painel envia
  cada um para aprovação da Meta e mostra o status (em análise, aprovado, rejeitado e o motivo).
- **Campanha com duas abas, E-mail e WhatsApp**, cada uma com um botão de ativar/desativar.
  Em cada aba, uma ou mais mensagens; cada mensagem tem modelo e data/hora (ou "assim que confirmar").
- **Público por segmentos**: a campanha escolhe um ou mais segmentos/listas. A mesma pessoa não
  recebe a mesma mensagem duas vezes. Quem tem e-mail e telefone recebe pelos dois canais.
- O envio de WhatsApp sai pela Cloud API com o token, Phone Number ID e WABA já guardados no cliente.

## Fora do escopo (agora)

- Confirmação de entregue/lido do WhatsApp (webhook da Cloud API). Fica para depois.
- Texto livre, respostas e conversas pela API Oficial (o atendimento continua na Evolution).
- Imagem, vídeo ou documento no cabeçalho do modelo; botões além de um link.
- Cobrança das mensagens de WhatsApp na fatura do painel: a Meta cobra direto no cartão da conta
  do WhatsApp da loja. *(decisão minha)*

## Anti-objetivos (seria falha mesmo funcionando)

- Quebrar ou duplicar o envio de e-mail das campanhas atuais, ou perder o histórico/desempenho das
  campanhas já enviadas.
- Mandar a mesma mensagem duas vezes para a mesma pessoa (reexecução de job, segmentos que se sobrepõem).
- Usar a Evolution (QR Code) para campanhas de marketing.
- Expor o token do WhatsApp em tela, log ou erro.

## Restrições

- Rails 7.2, Sidekiq, Postgres, deploy no Heroku (`mewtda-painel`), release roda `db:migrate`.
- Meta: iniciar conversa exige **modelo aprovado**. Categoria Marketing. Idioma `pt_BR`.
  Variáveis `{{1}}` precisam de exemplo na criação. O nome do modelo é minúsculo com `_`.
- Meta limita ritmo (erro 130429) e pode recusar marketing por destinatário (131049/131050):
  isso não é falha do painel, vira "bloqueado".
- Telefone brasileiro normalizado por `Whatsapp::Phone.normalize`; deduplicar pelo número normalizado.
- Limite diário de WhatsApp do plano (`daily_whatsapp_limit`) continua valendo e passa a contar
  também os envios de campanha pela Cloud API.

## Abordagens consideradas

- **A. Campanha com várias mensagens dentro (escolhida pelo Daniel).** Campanha guarda nome,
  segmentos e canais ativos; cada mensagem é um registro com canal, modelo, data/hora, status e
  contagens. O envio roda por mensagem. Prós: é o que a loja descreveu, cresce sem remendo.
  Contras: mexe na campanha de e-mail atual e exige migrar as campanhas existentes com cuidado.
- **B. Campanhas separadas agrupadas por uma "campanha-mãe".** Menos mudança no envio de e-mail,
  mas segmentos/ativação repetidos em cada filha e tela difícil de manter consistente. Descartada.

## Desenho

### Dados

- `whatsapp_templates`: `client_id`, `name` (nome na Meta), `label` (nome amigável), `category`
  (`MARKETING`), `language` (`pt_BR`), `body`, `body_example` (nome de exemplo para `{{1}}`),
  `footer` (opcional), `button_text` + `button_url` (opcional, um link), `meta_id`, `status`
  (`draft`, `pending`, `approved`, `rejected`, `paused`, `disabled`), `rejection_reason`, `synced_at`.
  Único por `[client_id, name]`.
- `campaign_segments` (campanha ↔ segmento, N:N). O `segment_id` atual vira uma linha aqui.
- `campaigns`: ganha `email_enabled` e `whatsapp_enabled`. Perde, depois da migração, o papel de
  guardar modelo e horário: `email_template_id`, `segment_id`, `send_mode`, `scheduled_at` e janela
  deixam de ser usados (remover numa migração posterior, não nesta).
- `campaign_messages`: `campaign_id`, `channel` (`email`/`whatsapp`), `email_template_id` ou
  `whatsapp_template_id`, `send_at` (vazio = assim que a campanha for confirmada), `position`,
  `status` (`draft`, `scheduled`, `sending`, `paused`, `sent`, `cancelled`), `next_run_at`,
  `audience_frozen_at`, `recipients_count`, `sent_count`, `failed_count`, `blocked_count`,
  `started_at`, `finished_at`.
- `campaign_recipients`: ganha `campaign_message_id`, `channel`, `phone` e `provider_message_id`
  (wamid); `email` passa a ser opcional. Índices únicos por `[campaign_message_id, email]` (e-mail) e
  `[campaign_message_id, phone]` (WhatsApp).
- **Migração das campanhas existentes**: cada campanha vira uma campanha com uma `campaign_message`
  de e-mail (mesmo modelo, `send_at` = `scheduled_at` ou `published_at`, mesmo status e contagens) e
  os destinatários existentes apontam para essa mensagem. `email_events` continua ligado a
  `campaign_recipient_id`, então o desempenho antigo não se perde.

### Status da campanha

Derivado das mensagens: rascunho até confirmar; "Enviando" se alguma estiver enviando; "Agendada"
se todas futuras; "Enviada" quando todas terminaram; "Cancelada" cancela todas as pendentes.

### Envio

- `Campaigns::TickJob` passa a acordar **mensagens** (`campaign_messages` executáveis com
  `next_run_at` vencido) e chama `Campaigns::DispatchJob` por mensagem, mantendo o mesmo esquema de
  reserva (lease) contra duas execuções ao mesmo tempo.
- Na primeira execução de cada mensagem, congela o público daquele canal a partir da união dos
  segmentos: e-mail = perfis com e-mail fora da lista de recusa (regra atual); WhatsApp = perfis com
  telefone que normaliza, deduplicados pelo número.
- E-mail: o caminho atual (SES), sem mudança de comportamento.
- WhatsApp: novo `Whatsapp::Cloud::Api` (HTTP para `graph.facebook.com`) com
  `send_template(to:, template:, first_name:)`. `{{1}}` = primeiro nome ou "cliente".
  Erros: 130429 → pausa curta e continua; 131049/131050/131047 → `blocked`; demais → `failed` com a
  mensagem da Meta (sem token). Para no limite diário de WhatsApp e continua no dia seguinte (como o e-mail).
- Envio para quando o cliente não tem a API Oficial configurada ou o modelo deixou de estar aprovado
  (pausa com aviso na campanha).

### Modelos de WhatsApp (Comunicação > WhatsApp)

- Lista com nome, status e prévia em balão de WhatsApp; criar, editar rascunho/rejeitado, duplicar,
  excluir (exclui na Meta também).
- "Enviar para aprovação" chama a API de modelos da WABA do cliente. Um job agendado (a cada 10 min)
  e a abertura da página atualizam o status dos modelos em análise.
- Aprovado não é editável (a Meta restringe); para mudar, duplica.
- Item novo no menu Comunicação: "WhatsApp", ao lado de "E-mail".

### Tela da campanha

- Nome; segmentos (seleção múltipla) com contagem de pessoas por canal.
- Abas **E-mail** e **WhatsApp**, cada uma com chave liga/desliga e lista de mensagens:
  modelo + "Assim que confirmar" ou data e hora; adicionar, remover, reordenar por data.
  A aba WhatsApp só deixa ativar com a API Oficial configurada e mostra só modelos aprovados.
- Resumo: pessoas por canal, mensagens e datas, custo do e-mail (como hoje) e aviso de que o
  WhatsApp é cobrado pela Meta.
- Teste: e-mail de teste (como hoje) e WhatsApp de teste para um número, usando o modelo escolhido.
- "Revisar e enviar" lista todas as mensagens com canal, modelo, data e público.
- O modo "dias e horários" (janela semanal) sai da tela. *(decisão minha, a confirmar com o Daniel)*

### Lista e desempenho

- Lista de campanhas mostra os canais ativos e o andamento por mensagem.
- Desempenho soma as mensagens; investimento continua só do e-mail; WhatsApp mostra enviados,
  falhas e bloqueados (sem entregue/lido por enquanto).

## Deixado para quem constrói

- Nomes exatos de classes, partials e JS, seguindo os padrões do repo (`ec-*`, `crm-*`, `cform-*`).
- Versão da Graph API (usar a mesma constante de `Meta::MonthlyCostFetcher` se fizer sentido).
- Antes de rodar a migração em produção: contar campanhas em andamento com modo janela e decidir com
  o Daniel o que fazer com elas.

## Entrega

Branch própria, testes (modelos, migração de dados, job de envio dos dois canais com a Cloud API
simulada, controller), PR para revisão. Sem deploy antes da revisão.
