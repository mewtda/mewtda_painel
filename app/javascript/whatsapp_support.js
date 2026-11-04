// Conversas do WhatsApp (Evolution Mewtda): abas por número, lista, chat com mídia.
// A gestão dos números fica em whatsapp_numbers.js (edição do cliente).
(() => {
  const $ = (id) => document.getElementById(id);
  const inbox = $("wa-inbox");
  if (!inbox || !inbox.querySelector(".wa-workspace")) return;
  const base = inbox.dataset.apiBase;
  const campaignId = inbox.dataset.campaignId || "";
  const stateLabels = {
    connected: "Conectado",
    qr: "Escaneie o QR",
    connecting: "Conectando…",
    disconnected: "Desconectado",
    disconnecting: "Desconectando…",
    unavailable: "Sem comunicação com o provedor",
  };
  const messageLabels = {
    queued: "Na fila",
    sending: "Enviando…",
    uncertain: "Envio sem confirmação",
    failed: "Não enviada",
    sent: "Enviada",
    delivered: "Entregue",
    read: "Lida",
    received: "Recebida",
  };
  // Selo do checkout de recuperação ligado à conversa.
  const checkoutLabels = {
    first_sent: "Recuperação 1ª enviada",
    second_sent: "Recuperação 2ª enviada",
    recovered: "Comprou",
    pending: "Recuperação aguardando",
    skipped: "Recuperação pulada",
  };
  const el = (tag, text, cls) => {
    const n = document.createElement(tag);
    if (text !== undefined) n.textContent = text;
    if (cls) n.className = cls;
    return n;
  };
  const palette = ["#00a884", "#53bdeb", "#ff7c5c", "#a78bfa", "#f59e0b", "#ef4f8a", "#25a3a3", "#7c9cff"];
  const initials = (name) =>
    (name || "?")
      .replace(/[^\p{L}\p{N} ]/gu, "")
      .trim()
      .split(/\s+/)
      .slice(0, 2)
      .map((w) => w[0])
      .join("")
      .toUpperCase() || "#";
  const paintAvatar = (node, name) => {
    let h = 0;
    for (const ch of name || "") h = (h * 31 + ch.codePointAt(0)) >>> 0;
    node.textContent = initials(name);
    node.style.setProperty("--wa-avatar", palette[h % palette.length]);
    return node;
  };
  const sameDay = (a, b) => a.toDateString() === b.toDateString();
  const hour = (value) =>
    value
      ? new Date(value).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" })
      : "";
  const dayLabel = (value) => {
    const d = new Date(value),
      today = new Date(),
      yesterday = new Date(Date.now() - 864e5);
    if (sameDay(d, today)) return "Hoje";
    if (sameDay(d, yesterday)) return "Ontem";
    return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" });
  };
  const listTime = (value) => {
    if (!value) return "";
    const label = dayLabel(value);
    return label === "Hoje" ? hour(value) : label;
  };
  const money = (value) =>
    value === null || value === undefined
      ? ""
      : Number(value).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const ticks = {
    queued: "fas fa-clock",
    sending: "fas fa-clock",
    sent: "fas fa-check",
    delivered: "fas fa-check-double",
    read: "fas fa-check-double",
    uncertain: "fas fa-circle-question",
    failed: "fas fa-circle-exclamation",
  };
  const error = (msg) => {
    $("wa-error").textContent = msg;
    $("wa-error").hidden = !msg;
  };
  const date = (value) =>
    value
      ? new Date(value).toLocaleString("pt-BR", {
          day: "2-digit",
          month: "2-digit",
          hour: "2-digit",
          minute: "2-digit",
        })
      : "";
  async function api(path, options = {}) {
    const headers = {
      Accept: "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content,
      ...options.headers,
    };
    let response;
    try {
      response = await fetch(`${base}${path}`, {
        credentials: "same-origin",
        ...options,
        headers,
      });
    } catch (_) {
      throw new Error("Sem comunicação com o painel. Confira sua conexão e tente novamente.");
    }
    if (response.redirected || [401, 403, 404].includes(response.status)) {
      $("wa-messages").replaceChildren();
      $("wa-threads").replaceChildren();
      $("wa-contact-panel").hidden = true;
      $("wa-selected").hidden = true;
      const failure = new Error("Seu acesso mudou ou a sessão terminou. Entre novamente no painel.");
      failure.status = response.redirected ? 401 : response.status;
      throw failure;
    }
    const data = response.headers.get("content-type")?.includes("application/json")
      ? await response.json()
      : {};
    if (!response.ok) {
      const failure = new Error(
        data.error || "Não foi possível concluir. O conteúdo digitado foi preservado.",
      );
      failure.status = response.status;
      throw failure;
    }
    return data;
  }
  const json = (method, body) => ({
    method,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const safe =
    (fn) =>
    async (...args) => {
      try {
        await fn(...args);
      } catch (e) {
        error(e.message);
      }
    };
  let stopped = false;
  window.addEventListener("pagehide", () => {
    stopped = true;
    stopRecording();
  });
  function poll(fn, interval = 4000) {
    const tick = async () => {
      if (stopped) return;
      if (!document.hidden) await safe(fn)();
      setTimeout(tick, interval);
    };
    setTimeout(tick, interval);
  }
  let mediaRecorder, audioStream, recordedFile;
  function stopRecording() {
    if (mediaRecorder?.state === "recording") mediaRecorder.stop();
    audioStream?.getTracks().forEach((t) => t.stop());
  }

  let selected,
    generation = 0,
    messages = new Map(),
    before,
    afterId = 0,
    numbers = [],
    listPage = 1,
    draftNonce,
    draftRequest,
    busy = false;
  const drafts = new Map(); // Só em memória: texto de cliente nunca vai para o localStorage.
  const history = $("wa-history");
  const nearBottom = () => history.scrollHeight - history.scrollTop - history.clientHeight < 100;
  const scrollBottom = () => {
    history.scrollTop = history.scrollHeight;
    $("wa-new-indicator").hidden = true;
  };
  function saveDraft() {
    if (selected)
      drafts.set(selected.id, {
        text: $("wa-text").value,
        file: recordedFile || $("wa-file").files[0],
        nonce: draftNonce,
        request: draftRequest,
      });
  }
  function setFiles(file) {
    recordedFile = file;
    $("wa-file").value = "";
    $("wa-file-name").textContent = file?.name || "";
    $("wa-clear-file").hidden = !file;
  }
  function lockDraft(locked) {
    $("wa-text").readOnly = locked;
    ["wa-file", "wa-clear-file", "wa-record"].forEach((id) => {
      $(id).disabled = locked;
    });
  }
  async function refreshList(append = false) {
    const p = new URLSearchParams({
      q: $("wa-search").value,
      connection_id: $("wa-number").value,
      state: $("wa-state").value,
      unread: $("wa-unread").checked ? "1" : "",
      page: listPage,
    });
    if (campaignId) p.set("campaign_id", campaignId);
    const result = await api(`/conversations.json?${p}`);
    numbers = result.connections;
    renderTabs();
    if (!append) $("wa-threads").replaceChildren();
    result.conversations.forEach((c) => {
      const button = el("button", undefined, `wa-thread ${selected?.id === c.id ? "selected" : ""}`);
      button.type = "button";
      if (c.unread_count) button.classList.add("has-unread");
      const body = el("span", undefined, "wa-thread-body"),
        top = el("span", undefined, "wa-thread-top"),
        bottom = el("span", undefined, "wa-thread-bottom");
      top.append(el("strong", c.name), el("time", listTime(c.last_message_at)));
      bottom.append(el("small", c.last_message_preview || c.phone || "Sem mensagens"));
      if (c.unread_count) bottom.append(el("span", c.unread_count, "wa-badge"));
      const foot = el("em", undefined, "wa-thread-number");
      foot.append(document.createTextNode(c.connection_name));
      if (c.checkout) foot.append(checkoutBadge(c.checkout));
      body.append(top, bottom, foot);
      button.append(paintAvatar(el("span", undefined, "wa-avatar"), c.name), body);
      button.onclick = safe(() => selectConversation(c.id));
      // Finalizar (ou reabrir) direto da lista, sem abrir a conversa.
      const row = el("div", undefined, "wa-thread-row");
      const closed = c.state === "closed";
      const quick = el("button", undefined, `wa-thread-finish${closed ? " is-closed" : ""}`);
      quick.type = "button";
      quick.title = closed ? "Reabrir conversa" : "Marcar como finalizada";
      quick.setAttribute("aria-label", `${quick.title}: ${c.name}`);
      quick.append(el("i", undefined, closed ? "fas fa-rotate-left" : "fas fa-check"));
      quick.onclick = safe(async (e) => {
        e.stopPropagation();
        quick.disabled = true;
        await api(`/conversations/${c.id}`, json("PATCH", { operation: closed ? "reopen" : "close" }));
        row.classList.add("is-leaving");
        if (selected?.id === c.id) await refreshSelected();
        await refreshList();
      });
      row.append(button, quick);
      $("wa-threads").append(row);
    });
    if (!result.conversations.length && !append)
      $("wa-threads").append(
        el(
          "p",
          numbers.length
            ? "Nenhuma conversa para este filtro."
            : "Nenhum número autorizado. Peça acesso à administração.",
          "wa-empty",
        ),
      );
    $("wa-more-conversations").hidden = !result.more;
  }
  function checkoutBadge(checkout) {
    const badge = el("span", undefined, `wa-checkout-badge is-${checkout.status}`);
    badge.append(
      el("i", undefined, checkout.status === "recovered" ? "fas fa-bag-shopping" : "fas fa-cart-shopping"),
      document.createTextNode(` ${checkoutLabels[checkout.status] || checkout.status}`),
    );
    return badge;
  }
  function renderCheckout(c) {
    const slot = $("wa-checkout-badge");
    slot.hidden = !c.checkout;
    slot.replaceChildren();
    if (c.checkout) {
      slot.className = `wa-checkout-badge is-${c.checkout.status}`;
      slot.append(...checkoutBadge(c.checkout).childNodes);
    }
    $("wa-checkout-line").textContent = c.checkout
      ? `Carrinho de ${money(c.checkout.total_price)} · ${checkoutLabels[c.checkout.status] || c.checkout.status}`
      : "";
    const panel = $("wa-checkout");
    panel.replaceChildren();
    if (!c.checkout) return;
    panel.append(
      el("label", "Recuperação de carrinho"),
      el("strong", money(c.checkout.total_price)),
      el("p", checkoutLabels[c.checkout.status] || c.checkout.status),
    );
    if (c.checkout.recovery_url) {
      const a = el("a", "Abrir link do carrinho");
      a.href = c.checkout.recovery_url;
      a.target = "_blank";
      a.rel = "noopener";
      panel.append(a);
    }
  }
  function renderAutoReply(c) {
    const b = $("wa-auto-reply");
    if (!b) return;
    b.hidden = !c.auto_reply_available;
    b.classList.toggle("is-on", !!c.auto_reply_paused);
    b.setAttribute("aria-pressed", c.auto_reply_paused ? "true" : "false");
    b.replaceChildren(
      el("i", undefined, c.auto_reply_paused ? "fas fa-play" : "fas fa-pause"),
      document.createTextNode(
        c.auto_reply_paused ? " Retomar resposta automática" : " Pausar resposta automática",
      ),
    );
  }
  function renderHeader(c) {
    selected = c;
    $("wa-contact-name").textContent = c.name;
    paintAvatar($("wa-contact-avatar"), c.name);
    paintAvatar($("wa-contact-avatar-lg"), c.name);
    $("wa-company-number").textContent =
      `Pelo número ${c.connection_name}${c.connection_phone ? " · " + c.connection_phone : ""} · ${stateLabels[c.connection_state] || c.connection_state}`;
    $("wa-close").replaceChildren(
      el("i", undefined, c.state === "closed" ? "fas fa-rotate-left" : "fas fa-circle-check"),
      document.createTextNode(c.state === "closed" ? " Reabrir" : " Finalizar"),
    );
    $("wa-close").classList.toggle("is-finish", c.state !== "closed");
    renderCheckout(c);
    renderAutoReply(c);
    $("wa-contact-phone").textContent = c.phone || "Telefone ainda não informado pelo WhatsApp";
    $("wa-send").disabled = busy || c.connection_state !== "connected";
  }
  function renderMedia(m, bubble) {
    if (m.kind === "image" || m.kind === "sticker") {
      const image = el("img", undefined, m.kind === "sticker" ? "wa-sticker" : undefined);
      image.src = m.media_url;
      image.alt = m.filename || (m.kind === "sticker" ? "Figurinha" : "Imagem recebida");
      image.loading = "lazy";
      bubble.append(image);
    } else if (m.kind === "audio") {
      const audio = el("audio");
      audio.src = m.media_url;
      audio.controls = true;
      audio.preload = "none";
      bubble.append(audio);
    } else if (m.kind === "video") {
      const video = el("video");
      video.src = m.media_url;
      video.controls = true;
      video.preload = "metadata";
      bubble.append(video);
    }
    if (m.kind === "sticker") return;
    const link = el("a", m.filename || "Baixar arquivo");
    link.href = m.media_url;
    link.download = m.filename || "";
    bubble.append(link);
  }
  function renderMessages(rows, { older = false } = {}) {
    const wasBottom = nearBottom(),
      oldHeight = history.scrollHeight,
      oldTop = history.scrollTop;
    rows.forEach((m) => {
      messages.set(m.id, m);
    });
    // Elementos existentes só mudam se a mensagem mudou: o polling não reinicia um áudio tocando.
    const container = $("wa-messages");
    let lastDay = null,
      lastDirection = null;
    [...messages.values()]
      .sort((a, b) => new Date(a.sent_at) - new Date(b.sent_at) || a.id - b.id)
      .forEach((m, index) => {
        let node = document.getElementById(`wa-message-${m.id}`);
        const signature = JSON.stringify(m);
        if (!node || node.dataset.signature !== signature) {
          const row = el("article", undefined, `wa-message ${m.direction}`);
          row.id = `wa-message-${m.id}`;
          row.dataset.signature = signature;
          const next = el("div", undefined, `wa-bubble is-${m.state}`);
          row.append(next);
          if (m.origin === "ai") next.classList.add("by-auto");
          if (m.direction === "outgoing" && (m.author || m.origin === "ai")) {
            const author = el("span", m.author || "", "wa-author");
            if (m.origin === "ai") author.prepend(el("span", "automática", "wa-auto-seal"));
            next.append(author);
          }
          if (m.body) next.append(el("p", m.body));
          if (m.media_url) renderMedia(m, next);
          else if (m.media_state)
            next.append(
              el(
                "p",
                {
                  pending: "Carregando arquivo…",
                  rejected: "Arquivo não permitido ou acima de 16 MB.",
                  unavailable: "Arquivo indisponível no provedor.",
                }[m.media_state] || "Arquivo indisponível.",
              ),
            );
          if (m.kind === "unsupported")
            next.append(el("p", "Este tipo de mensagem pode ser consultado no celular."));
          const meta = el("small", undefined, "wa-meta");
          meta.title = `${date(m.sent_at)} · ${messageLabels[m.state] || m.state}`;
          meta.append(el("time", hour(m.sent_at)));
          if (m.direction === "outgoing" && ticks[m.state]) {
            const tick = el("i", undefined, `${ticks[m.state]} wa-tick is-${m.state}`);
            tick.setAttribute("aria-hidden", "true");
            meta.append(tick);
          }
          meta.append(el("span", messageLabels[m.state] || m.state, "visually-hidden"));
          next.append(meta);
          if (["failed", "uncertain"].includes(m.state)) {
            next.append(
              el(
                "p",
                m.state === "uncertain"
                  ? "O WhatsApp pode ter recebido este envio. Confira no celular antes de enviar novamente. Não houve repetição automática."
                  : "O envio não começou. O texto e o arquivo continuam disponíveis abaixo.",
                "wa-send-warning",
              ),
            );
            const restore = el("button", "Copiar texto para o campo", "btn btn-sm btn-light");
            restore.type = "button";
            restore.onclick = () => {
              if (draftRequest) {
                error("Consulte o envio pendente clicando em Enviar antes de alterar o rascunho.");
                return;
              }
              if (!$("wa-text").value || confirm("Substituir o texto atual pelo desta mensagem?")) {
                $("wa-text").value = m.body || "";
                grow();
                draftNonce = null;
              }
            };
            next.append(restore);
            if (m.state === "failed") {
              const retry = el("button", "Tentar enviar", "btn btn-sm btn-outline-secondary");
              retry.type = "button";
              retry.onclick = safe(async () => {
                await api(
                  `/conversations/${selected.id}/messages/${m.id}/retry_send`,
                  json("POST", {}),
                );
                await refreshSelected();
              });
              next.append(retry);
            }
          }
          if (node) node.replaceWith(row);
          node = row;
        }
        const current = container.children[index];
        if (current !== node) container.insertBefore(node, current || null);
        // Separador de dia, como no WhatsApp: só na primeira mensagem de cada dia.
        const label = dayLabel(m.sent_at);
        if (label === lastDay) delete node.dataset.day;
        else node.dataset.day = label;
        // A "pontinha" do balão só aparece na primeira mensagem de uma sequência.
        node.classList.toggle("wa-first", label !== lastDay || m.direction !== lastDirection);
        lastDay = label;
        lastDirection = m.direction;
      });
    if (older) history.scrollTop = oldTop + (history.scrollHeight - oldHeight);
    else if (wasBottom) scrollBottom();
    else if (rows.some((m) => m.id > afterId)) $("wa-new-indicator").hidden = false;
  }
  async function selectConversation(id) {
    if (busy) return;
    saveDraft();
    stopRecording();
    const ticket = ++generation;
    const c = await api(`/conversations/${id}.json`);
    if (ticket !== generation) return;
    messages = new Map();
    $("wa-messages").replaceChildren();
    renderHeader(c);
    $("wa-empty").hidden = true;
    $("wa-selected").hidden = false;
    $("wa-contact-panel").hidden = true;
    document.querySelector(".wa-workspace").classList.add("chat-open");
    const draft = drafts.get(id);
    $("wa-text").value = draft?.text || "";
    grow();
    setFiles(draft?.file);
    draftNonce = draft?.nonce;
    draftRequest = draft?.request || null;
    lockDraft(!!draftRequest);
    const result = await api(`/conversations/${id}/messages.json`);
    if (ticket !== generation) return;
    before = result.before;
    afterId = result.after_id;
    renderMessages(result.messages);
    $("wa-older").hidden = !before;
    scrollBottom();
    await markRead();
  }
  async function markRead() {
    if (selected && !document.hidden && nearBottom())
      await api(`/conversations/${selected.id}/read`, json("POST", { last_message_id: afterId }));
  }
  async function refreshSelected() {
    if (!selected) return;
    const id = selected.id,
      ticket = generation;
    const ids = [...messages.keys()].slice(-200);
    const p = new URLSearchParams({ after_id: afterId });
    ids.forEach((i) => p.append("ids[]", i));
    const result = await api(`/conversations/${id}/messages.json?${p}`);
    if (ticket !== generation) return;
    renderMessages(result.messages);
    afterId = result.after_id;
    const c = await api(`/conversations/${id}.json`);
    if (ticket !== generation) return;
    renderHeader(c);
    await markRead();
  }
  $("wa-older").onclick = safe(async () => {
    if (!before || !selected) return;
    const ticket = generation;
    const result = await api(
      `/conversations/${selected.id}/messages.json?before=${encodeURIComponent(before)}`,
    );
    if (ticket !== generation) return;
    renderMessages(result.messages, { older: true });
    before = result.before;
    $("wa-older").hidden = !before;
  });
  $("wa-new-indicator").onclick = safe(async () => {
    scrollBottom();
    await markRead();
  });
  $("wa-back").onclick = () => {
    document.querySelector(".wa-workspace").classList.remove("chat-open");
  };
  $("wa-contact-toggle").onclick = () => {
    $("wa-contact-panel").hidden = !$("wa-contact-panel").hidden;
    $("wa-contact-toggle").setAttribute("aria-expanded", !$("wa-contact-panel").hidden);
  };
  $("wa-contact-hide").onclick = () => {
    $("wa-contact-panel").hidden = true;
    $("wa-contact-toggle").setAttribute("aria-expanded", "false");
  };
  $("wa-close").onclick = safe(async () => {
    if (!selected) return;
    const c = await api(
      `/conversations/${selected.id}`,
      json("PATCH", { operation: selected.state === "closed" ? "reopen" : "close" }),
    );
    renderHeader(c);
    await refreshList();
  });
  if ($("wa-auto-reply"))
    $("wa-auto-reply").onclick = safe(async () => {
      if (!selected) return;
      const c = await api(
        `/conversations/${selected.id}/auto_reply`,
        json("PATCH", { paused: !selected.auto_reply_paused }),
      );
      renderHeader(c);
    });
  $("wa-file").onchange = () => {
    recordedFile = null;
    const file = $("wa-file").files[0];
    $("wa-file-name").textContent = file?.name || "";
    $("wa-clear-file").hidden = !file;
    draftNonce = null;
  };
  $("wa-clear-file").onclick = () => {
    setFiles(null);
    draftNonce = null;
  };
  $("wa-text").oninput = () => {
    if (!draftRequest) draftNonce = null;
  };
  $("wa-compose").onsubmit = safe(async (e) => {
    e.preventDefault();
    if (busy || !selected) return;
    if (mediaRecorder?.state === "recording") throw new Error("Pare a gravação antes de enviar.");
    const file = recordedFile || $("wa-file").files[0];
    if (file?.size > 16 * 1024 * 1024) throw new Error("O arquivo deve ter até 16 MB.");
    if (!$("wa-text").value.trim() && !file) return;
    const id = selected.id;
    // Guarda o mesmo pedido e nonce se a resposta se perder: reenviar consulta, não duplica.
    if (!draftRequest) {
      draftNonce ||= crypto.randomUUID();
      const form = new FormData();
      form.set("client_nonce", draftNonce);
      form.set("body", $("wa-text").value);
      if (file) form.set("file", file);
      draftRequest = form;
    }
    busy = true;
    $("wa-send").disabled = true;
    lockDraft(true);
    try {
      const message = await api(`/conversations/${id}/messages`, {
        method: "POST",
        body: draftRequest,
      });
      renderMessages([message]);
      $("wa-text").value = "";
      grow();
      setFiles(null);
      draftNonce = null;
      draftRequest = null;
      lockDraft(false);
      drafts.delete(id);
      error("");
      refreshSelected().catch(() => {});
      scrollBottom();
    } catch (failure) {
      if (failure.status && failure.status < 500) {
        draftRequest = null;
        draftNonce = null;
        lockDraft(false);
      } else {
        failure = new Error(
          "A resposta do painel não chegou. Clique em Enviar novamente para consultar o mesmo envio, sem duplicar.",
        );
      }
      throw failure;
    } finally {
      busy = false;
      $("wa-send").disabled = selected?.connection_state !== "connected";
    }
  });
  const mime =
    window.MediaRecorder &&
    ["audio/webm;codecs=opus", "audio/ogg;codecs=opus", "audio/mp4"].find((t) =>
      MediaRecorder.isTypeSupported(t),
    );
  $("wa-record").hidden = !mime || !navigator.mediaDevices?.getUserMedia;
  $("wa-record").onclick = safe(async () => {
    if (mediaRecorder?.state === "recording") {
      stopRecording();
      return;
    }
    audioStream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const chunks = [],
      id = selected?.id;
    mediaRecorder = new MediaRecorder(audioStream, { mimeType: mime });
    mediaRecorder.ondataavailable = (e) => {
      if (e.data.size) chunks.push(e.data);
    };
    mediaRecorder.onstop = () => {
      audioStream.getTracks().forEach((t) => t.stop());
      setRecording(false);
      if (selected?.id === id) {
        setFiles(
          new File(
            chunks,
            `audio.${mime.includes("ogg") ? "ogg" : mime.includes("mp4") ? "m4a" : "webm"}`,
            { type: mime },
          ),
        );
        draftNonce = null;
      }
    };
    mediaRecorder.start();
    setRecording(true);
    setTimeout(stopRecording, 60000);
  });
  // Uma aba para cada número: a lista carrega só as conversas do número aberto.
  const tabsRoot = $("wa-number-tabs");
  const tabButtons = () => [...tabsRoot.querySelectorAll(".wa-number-tab")];
  function setNumber(id) {
    $("wa-number").value = id ? String(id) : "";
    tabButtons().forEach((b) => {
      const on = b.dataset.id === String(id);
      b.classList.toggle("is-active", on);
      b.setAttribute("aria-selected", on ? "true" : "false");
    });
    try {
      localStorage.setItem("mewtda:wa-number", String(id));
    } catch (_) {}
  }
  function renderTabs() {
    numbers.forEach((n) => {
      const b = tabsRoot.querySelector(`[data-id="${n.id}"]`);
      if (!b) return;
      b.querySelector(".wa-number-dot").classList.toggle("is-on", !!n.connected);
      const count = b.querySelector(".wa-number-count");
      count.hidden = !n.unread_count;
      count.textContent = n.unread_count;
      count.title = `${n.unread_count} conversa(s) com mensagens não lidas`;
    });
  }
  tabButtons().forEach((b) => {
    b.onclick = safe(async () => {
      if (b.dataset.id === $("wa-number").value) return;
      setNumber(b.dataset.id);
      listPage = 1;
      $("wa-threads").replaceChildren();
      await refreshList();
    });
  });
  {
    let stored = null;
    try {
      stored = localStorage.getItem("mewtda:wa-number");
    } catch (_) {}
    const first = tabButtons().find((b) => b.dataset.id === stored) || tabButtons()[0];
    if (first) setNumber(first.dataset.id);
  }
  // Link direto para uma conversa (?c=ID).
  const deepLink = Number(new URLSearchParams(location.search).get("c"));
  if (deepLink) {
    $("wa-state").value = "";
    setTimeout(
      safe(async () => {
        await selectConversation(deepLink);
        if (selected && String(selected.connection_id) !== $("wa-number").value) {
          setNumber(selected.connection_id);
          await refreshList();
        }
      }),
      300,
    );
  }
  function setRecording(on) {
    const b = $("wa-record");
    b.classList.toggle("is-recording", on);
    b.title = on ? "Parar gravação" : "Gravar áudio";
    b.setAttribute("aria-label", b.title);
    b.firstElementChild.className = on ? "fas fa-stop" : "fas fa-microphone";
  }
  // Tema claro/escuro das conversas (preferência só deste navegador); padrão segue o tema do painel.
  const applyTheme = (theme) => {
    inbox.dataset.waTheme = theme;
    const next = theme === "dark" ? "claro" : "escuro";
    $("wa-theme-toggle").title = `Usar tema ${next}`;
    $("wa-theme-toggle").setAttribute("aria-label", `Usar tema ${next}`);
    $("wa-theme-toggle").firstElementChild.className = theme === "dark" ? "fas fa-sun" : "fas fa-moon";
  };
  const panelTheme = document.documentElement.classList.contains("theme-dark") ? "dark" : "light";
  try {
    const stored = localStorage.getItem("mewtda:wa-theme");
    applyTheme(stored === "light" || stored === "dark" ? stored : panelTheme);
  } catch (_) {
    applyTheme(panelTheme);
  }
  $("wa-theme-toggle").onclick = () => {
    const theme = inbox.dataset.waTheme === "dark" ? "light" : "dark";
    applyTheme(theme);
    try {
      localStorage.setItem("mewtda:wa-theme", theme);
    } catch (_) {}
  };
  // A caixa de texto cresce com a mensagem, até 6 linhas.
  function grow() {
    const t = $("wa-text");
    t.style.height = "auto";
    t.style.height = `${Math.min(t.scrollHeight, 140)}px`;
  }
  $("wa-text").addEventListener("input", grow);
  $("wa-new-side").onclick = () => $("wa-new").click();
  let debounce;
  ["wa-search", "wa-number", "wa-state", "wa-unread"].forEach((id) => {
    $(id).addEventListener(id === "wa-search" ? "input" : "change", () => {
      clearTimeout(debounce);
      debounce = setTimeout(
        safe(async () => {
          listPage = 1;
          await refreshList();
        }),
        250,
      );
    });
  });
  $("wa-more-conversations").onclick = safe(async () => {
    listPage += 1;
    await refreshList(true);
  });
  $("wa-new").onclick = () => {
    $("wa-start-number").replaceChildren(new Option("Escolha um número", ""));
    numbers.forEach((n) =>
      $("wa-start-number").add(new Option(`${n.name} · ${n.phone || "não conectado"}`, n.id)),
    );
    $("wa-start-number").value = $("wa-number").value;
    $("wa-new-dialog").showModal();
  };
  $("wa-cancel-new").onclick = () => $("wa-new-dialog").close();
  $("wa-start").onsubmit = safe(async (e) => {
    e.preventDefault();
    const c = await api(
      "/conversations",
      json("POST", {
        connection_id: $("wa-start-number").value,
        phone: $("wa-start-phone").value,
      }),
    );
    $("wa-new-dialog").close();
    await selectConversation(c.id);
    listPage = 1;
    await refreshList();
  });
  safe(refreshList)();
  poll(async () => {
    if (listPage === 1) await refreshList();
    await refreshSelected();
  });
})();
