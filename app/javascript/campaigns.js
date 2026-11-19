(() => {
  const form = document.getElementById("campaign-form");
  if (!form) return;

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const csrf = () => $('meta[name="csrf-token"]')?.content;
  const number = (value) => Number(value || 0).toLocaleString("pt-BR");
  const plural = (count, one, many) => `${number(count)} ${count === 1 ? one : many}`;

  const SAVE_DELAY_MS = 600;
  const frame = $("#ec-frame");
  const stage = $("#ec-stage");
  const savedText = $("#ec-saved-text");
  const saved = $("#ec-saved");
  const reviewButton = $("#ec-review");
  const waTemplates = JSON.parse($("#ec-wa-templates")?.textContent || "{}");
  let timer;
  let controller;
  let pending = false;
  let saving = false;
  let failed = false;
  let lastData = null;
  let selected = null; // { id, channel }

  const setStatus = (text, state) => {
    savedText.textContent = text;
    saved.dataset.state = state;
  };

  // ---------- Abas e chaves dos canais ----------
  const showTab = (channel) => {
    $$("[data-tab]", form).forEach((tab) => {
      const on = tab.dataset.tab === channel;
      tab.classList.toggle("is-active", on);
      tab.setAttribute("aria-selected", on);
    });
    $$("[data-channel-panel]", form).forEach((panel) => { panel.hidden = panel.dataset.channelPanel !== channel; });
  };

  const syncToggles = () => {
    $$("[data-channel-toggle]", form).forEach((toggle) => {
      const channel = toggle.dataset.channelToggle;
      const body = $(`[data-channel-body="${channel}"]`, form);
      if (body) body.hidden = !toggle.checked;
      const state = $(`[data-tab-state="${channel}"]`, form);
      state.textContent = toggle.checked ? "Ativo" : "Desligado";
      state.classList.toggle("is-on", toggle.checked);
    });
  };

  $$("[data-tab]", form).forEach((tab) => tab.addEventListener("click", () => showTab(tab.dataset.tab)));

  // ---------- Mensagens ----------
  const renumber = () => {
    $$("[data-messages]", form).forEach((list) => {
      $$(".ec-msg", list).forEach((row, index) => { $("[data-msg-number]", row).textContent = index + 1; });
    });
  };

  const syncWhen = (row) => {
    const later = $('input[data-msg-when][value="0"]', row)?.checked;
    $("[data-msg-date]", row).hidden = !later;
  };

  const addMessage = async (button) => {
    button.disabled = true;
    const body = new FormData();
    body.append("channel", button.dataset.addMessage);
    const response = await fetch(button.dataset.url, {
      method: "POST", body, headers: { Accept: "text/html", "X-CSRF-Token": csrf() },
    }).catch(() => null);
    button.disabled = false;
    if (!response?.ok) return setStatus("Não foi possível adicionar a mensagem. Tente de novo.", "error");

    const holder = document.createElement("div");
    holder.innerHTML = await response.text();
    const row = holder.firstElementChild;
    $(`[data-messages="${button.dataset.addMessage}"]`, form).append(row);
    renumber();
    selectMessage(row);
    schedule();
  };

  const removeMessage = async (row) => {
    const button = $("[data-msg-remove]", row);
    button.disabled = true;
    await flush();
    const response = await fetch(button.dataset.url, {
      method: "DELETE", headers: { Accept: "application/json", "X-CSRF-Token": csrf() },
    }).catch(() => null);
    if (!response?.ok) {
      button.disabled = false;
      return setStatus("Não foi possível remover a mensagem. Tente de novo.", "error");
    }
    if (selected?.id === row.dataset.messageId) selectMessage(null);
    row.remove();
    renumber();
    renderSummary(await response.json());
  };

  // ---------- Prévia e testes da mensagem selecionada ----------
  const showKind = (kind) => {
    $$("[data-preview-kind]").forEach((node) => { node.hidden = node.dataset.previewKind !== kind; });
  };

  const templateOf = (row) => $("[data-msg-template]", row)?.value || "";

  const selectMessage = (row) => {
    $$(".ec-msg", form).forEach((other) => other.classList.toggle("is-selected", other === row));
    if (!row) {
      selected = null;
      $("#ec-preview-title").textContent = "Prévia";
      return showKind("none");
    }
    selected = { id: row.dataset.messageId, channel: row.dataset.channel };
    const label = `${row.dataset.channel === "whatsapp" ? "WhatsApp" : "E-mail"} ${$("[data-msg-number]", row).textContent}`;
    $("#ec-preview-title").textContent = `Prévia — ${label}`;
    showKind(row.dataset.channel);
    refreshPreview(row);
  };

  const refreshPreview = (row) => {
    if (!row || selected?.id !== row.dataset.messageId) return;
    const templateId = templateOf(row);

    if (row.dataset.channel === "whatsapp") {
      const data = waTemplates[templateId];
      $("[data-wt-preview-body]").textContent = data ? data.body : "Escolha um modelo aprovado para ver a prévia.";
      const footer = $("[data-wt-preview-footer]");
      footer.textContent = data?.footer || "";
      footer.hidden = !data?.footer;
      $("[data-wt-preview-button-text]").textContent = data?.button || "";
      $("[data-wt-preview-button]").hidden = !data?.button;
      return;
    }

    if (!templateId) {
      frame.removeAttribute("src");
      return;
    }
    const src = `${form.dataset.previewUrl}?message_id=${row.dataset.messageId}&template=${templateId}`;
    if (frame.dataset.src !== src) {
      frame.dataset.src = src;
      stage.classList.add("is-live-loading");
      // espera o autosave gravar o modelo antes de pedir a prévia
      waitSaved().then(() => { frame.src = `${src}&t=${Date.now()}`; });
    }
  };

  const fitFrame = () => {
    const doc = frame.contentDocument;
    if (!doc?.documentElement) return;
    frame.style.height = "0px";
    frame.style.height = `${doc.documentElement.scrollHeight}px`;
    $$("img", doc).forEach((image) => image.addEventListener("load", fitFrame, { once: true }));
  };

  frame.addEventListener("load", () => {
    stage.classList.remove("is-live-loading");
    fitFrame();
  });

  $$("[data-ec-device]").forEach((button) => {
    button.addEventListener("click", () => {
      $$("[data-ec-device]").forEach((other) => other.classList.toggle("active", other === button));
      stage.classList.toggle("is-mobile", button.dataset.ecDevice === "mobile");
      setTimeout(fitFrame, 50);
    });
  });

  const postTest = async (button, status, fields) => {
    button.disabled = true;
    status.textContent = "Enviando…";
    status.className = "ec-hint";
    await flush();
    const body = new FormData();
    Object.entries(fields).forEach(([key, value]) => body.append(key, value));
    const response = await fetch(button.dataset.url, {
      method: "POST", body, headers: { Accept: "application/json", "X-CSRF-Token": csrf() },
    }).catch(() => null);
    const result = await response?.json().catch(() => ({}));
    button.disabled = false;
    status.textContent = response?.ok ? result.message : result?.error || "Não foi possível enviar o teste.";
    status.className = response?.ok ? "ec-hint ec-hint--ok" : "ec-hint ec-hint--error";
  };

  const sendEmailTest = () => postTest($("#ec-test-send"), $("#ec-test-status"),
    { test_email: $("#ec-test-email").value.trim(), message_id: selected?.id || "" });

  const sendWhatsappTest = () => {
    const row = selected && $(`.ec-msg[data-message-id="${selected.id}"]`, form);
    postTest($("#ec-test-wa-send"), $("#ec-test-wa-status"),
      { phone: $("#ec-test-phone").value.trim(), whatsapp_template_id: row ? templateOf(row) : "" });
  };

  $("#ec-test-send").addEventListener("click", sendEmailTest);
  $("#ec-test-wa-send").addEventListener("click", sendWhatsappTest);
  [["#ec-test-email", sendEmailTest], ["#ec-test-phone", sendWhatsappTest]].forEach(([selector, send]) => {
    $(selector).addEventListener("keydown", (event) => {
      if (event.key !== "Enter") return;
      event.preventDefault();
      send();
    });
  });

  // ---------- Resumo ----------
  const element = (tag, text) => Object.assign(document.createElement(tag), { textContent: text });

  const renderAudience = (data) => {
    const { email, whatsapp } = data.channels;
    $("#ec-audience").hidden = !data.steps.audience;
    $('[data-summary="email-recipients"]').textContent = number(email.recipients);
    $('[data-summary="whatsapp-recipients"]').textContent = number(whatsapp.recipients);
    $('[data-audience="email"]').hidden = !email.enabled;
    $('[data-audience="whatsapp"]').hidden = !whatsapp.enabled;

    const consent = $("[data-summary-consent]");
    consent.textContent = email.enabled && email.recipients
      ? (email.not_subscribed
        ? `${number(email.subscribed)} já aceitaram receber promoções · ${number(email.not_subscribed)} ainda não aceitaram`
        : "Todos já aceitaram receber promoções")
      : "";
    const left = email.suppressed + email.without_email;
    $("[data-summary-excluded]").textContent = email.enabled && left
      ? `${number(left)} ficaram de fora do e-mail: pediram para sair da lista ou não têm e-mail` : "";
    $("[data-summary-without-phone]").textContent = whatsapp.enabled && whatsapp.without_phone
      ? `${number(whatsapp.without_phone)} ficaram de fora do WhatsApp: sem celular válido no cadastro` : "";
  };

  const channelLine = (channel) => (channel.enabled
    ? `${plural(channel.recipients, "pessoa", "pessoas")} · ${plural(channel.messages, "mensagem", "mensagens")}`
    : "Desligado");

  const limitLine = (channel, unit) => (channel.enabled && channel.daily_limit
    ? `limite: ${number(channel.daily_limit)} ${unit}/dia (${number(channel.used_today)} usados hoje)` : "");

  const renderLimitWarning = (data) => {
    const warn = $("#ec-limit-warn");
    const over = ["email", "whatsapp"].filter((key) => {
      const channel = data.channels[key];
      return channel.enabled && channel.daily_limit && channel.recipients * channel.messages > channel.daily_limit;
    });
    warn.hidden = !over.length;
    if (!over.length) return;
    const names = over.map((key) => (key === "email" ? "e-mails" : "mensagens de WhatsApp")).join(" e ");
    warn.replaceChildren(
      element("strong", "Passa do seu limite diário"),
      element("p", `Seu plano tem um limite diário de ${names}. O que não couber no dia continua sozinho no dia seguinte, às 08:00.`),
    );
  };

  const renderSummary = (data) => {
    lastData = data;
    reviewButton.disabled = !data.ready;
    renderAudience(data);
    const { email, whatsapp } = data.channels;
    $('[data-summary="email-line"]').textContent = channelLine(email);
    $('[data-summary="email-sub"]').textContent = limitLine(email, "e-mails");
    $('[data-summary="whatsapp-line"]').textContent = whatsapp.configured ? channelLine(whatsapp) : "API Oficial não configurada";
    $('[data-summary="whatsapp-sub"]').textContent = limitLine(whatsapp, "mensagens");
    $('[data-summary="cost"]').textContent = email.enabled ? email.cost : "—";
    $('[data-summary="timing"]').textContent = data.timing;
    $('[data-summary="whatsapp-cost"]').hidden = !whatsapp.enabled;
    renderLimitWarning(data);

    $$("[data-step]", form).forEach((step) => step.classList.toggle("is-done", Boolean(data.steps[step.dataset.step])));
    $("#ec-missing-list").replaceChildren(...data.missing.map((text) => element("li", text)));
    $("#ec-missing").hidden = !data.missing.length;
  };

  // ---------- Autosave ----------
  let savedResolvers = [];
  const waitSaved = () => (pending || saving ? new Promise((resolve) => savedResolvers.push(resolve)) : Promise.resolve());
  const releaseWaiters = () => {
    savedResolvers.forEach((resolve) => resolve());
    savedResolvers = [];
  };

  const save = async () => {
    controller?.abort();
    controller = new AbortController();
    pending = false;
    saving = true;
    failed = false;
    setStatus("Salvando…", "saving");

    try {
      const response = await fetch(form.action, {
        method: "POST", body: new FormData(form), signal: controller.signal,
        headers: { Accept: "application/json", "X-CSRF-Token": csrf() },
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error);

      renderSummary(data);
      setBusy(false);
      setStatus(`Salvo às ${data.saved_at}`, "saved");
      saving = false;
      if (!pending) releaseWaiters();
    } catch (error) {
      if (error.name === "AbortError") return;
      saving = false;
      failed = true;
      setBusy(false);
      releaseWaiters();
      setStatus(error.message && error.message !== "Failed to fetch"
        ? `Não foi possível salvar: ${error.message}` : "Não foi possível salvar. Tentando de novo ao próximo ajuste.", "error");
    }
  };

  const schedule = (delay = SAVE_DELAY_MS) => {
    pending = true;
    setStatus("Salvando…", "saving");
    clearTimeout(timer);
    timer = setTimeout(save, delay);
  };

  // Grava agora o que estiver pendente (antes de testes e de remover mensagens).
  const flush = async () => {
    if (pending) {
      clearTimeout(timer);
      await save();
    } else if (saving) {
      await waitSaved();
    }
  };

  const busyAreas = $$(".ec-summary, #ec-audience");
  const setBusy = (busy) => busyAreas.forEach((area) => area.classList.toggle("ec-busy", busy));
  const isTestField = (target) => ["ec-test-email", "ec-test-phone"].includes(target.id);

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    schedule(0);
  });

  form.addEventListener("input", (event) => {
    if (isTestField(event.target)) return;
    if (event.target.matches('[name="campaign[segment_ids][]"]')) setBusy(true);
    schedule();
  });

  form.addEventListener("change", (event) => {
    const { target } = event;
    if (isTestField(target)) return;
    if (target.matches(".ec-seg input")) {
      target.closest(".ec-seg").classList.toggle("is-on", target.checked);
      setBusy(true);
    }
    if (target.matches("[data-channel-toggle]")) {
      syncToggles();
      setBusy(true);
    }
    const row = target.closest(".ec-msg");
    if (row) {
      if (target.matches("[data-msg-when]")) syncWhen(row);
      if (target.matches("[data-msg-template]")) {
        if (selected?.id !== row.dataset.messageId) selectMessage(row);
        else refreshPreview(row);
      }
    }
    schedule();
  });

  form.addEventListener("click", (event) => {
    const add = event.target.closest("[data-add-message]");
    if (add) return addMessage(add);
    const row = event.target.closest(".ec-msg");
    if (!row) return;
    if (event.target.closest("[data-msg-remove]")) return removeMessage(row);
    if (event.target.closest("[data-msg-preview]")) selectMessage(row);
  });

  // ---------- Revisão ----------
  const dialog = $("#ec-review-dialog");
  const submit = $("#ec-schedule-submit");
  const accept = $("#ec-accept");

  const openReview = () => {
    if (!lastData?.ready) return;
    const { email, whatsapp } = lastData.channels;
    const fill = (key, text) => { $(`[data-review="${key}"]`, dialog).textContent = text; };

    fill("name", form.elements["campaign[name]"].value);
    fill("segments", lastData.segments.join(", "));
    const people = [];
    if (email.enabled) people.push(`${plural(email.recipients, "pessoa", "pessoas")} por e-mail`);
    if (whatsapp.enabled) people.push(`${plural(whatsapp.recipients, "número", "números")} de WhatsApp`);
    fill("recipients", people.join(" · "));
    fill("cost", email.enabled ? email.cost : "—");
    $('[data-review="messages"]', dialog).replaceChildren(...lastData.messages.map((message) => {
      const item = document.createElement("li");
      item.append(element("strong", `${message.channel_label}: `), `${message.template || "sem modelo"} — ${message.when}`);
      return item;
    }));

    const consent = $("#ec-consent", dialog);
    const needsConsent = email.enabled && email.not_subscribed;
    consent.hidden = !needsConsent;
    accept.checked = false;
    if (needsConsent) {
      $('[data-review="consent"]', dialog).textContent =
        `Entendo que ${number(email.not_subscribed)} pessoas ainda não aceitaram receber promoções por e-mail e que a responsabilidade por esse envio é da loja.`;
    }
    submit.disabled = Boolean(needsConsent);
    dialog.showModal();
  };

  reviewButton.addEventListener("click", async () => {
    await flush();
    openReview();
  });
  accept.addEventListener("change", () => { submit.disabled = !accept.checked; });
  $("#ec-review-back").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
  $("#ec-schedule-form").addEventListener("submit", () => window.CrmLeaveGuard?.watch(() => false));

  window.CrmLeaveGuard?.watch(() => pending || saving || failed);
  syncToggles();
  $$(".ec-msg", form).forEach(syncWhen);
  showKind("none");
  save();
})();
