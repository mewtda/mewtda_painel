(() => {
  const form = document.getElementById("campaign-form");
  if (!form) return;

  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => Array.from(root.querySelectorAll(selector));
  const csrf = () => $('meta[name="csrf-token"]')?.content;
  const number = (value) => Number(value).toLocaleString("pt-BR");

  const SAVE_DELAY_MS = 600;
  const frame = $("#ec-frame");
  const stage = $("#ec-stage");
  const saved = $("#ec-saved");
  const savedText = $("#ec-saved-text");
  let timer;
  let controller;
  let pending = false;
  let saving = false;
  let failed = false;
  let lastData = null;
  const reviewButton = $("#ec-review");
  let currentTemplate = $('[name="campaign[email_template_id]"]', form)?.value || "";

  const setStatus = (text, state) => {
    savedText.textContent = text;
    saved.dataset.state = state;
  };

  const showModePanel = () => {
    const mode = $('[name="campaign[send_mode]"]:checked', form)?.value;
    $$("[data-mode-panel]", form).forEach((panel) => { panel.hidden = panel.dataset.modePanel !== mode; });
  };

  const renderAudience = (data) => {
    const audience = data.audience;
    $("#ec-audience").hidden = !data.steps.audience;
    $$('[data-summary="recipients"]').forEach((node) => { node.textContent = number(audience.recipients); });

    const consent = $("[data-summary-consent]");
    consent.textContent = audience.not_subscribed
      ? `${number(audience.subscribed)} já aceitaram receber promoções · ${number(audience.not_subscribed)} ainda não aceitaram`
      : audience.recipients ? "Todos já aceitaram receber promoções" : "";

    const left = audience.suppressed + audience.without_email;
    $("[data-summary-excluded]").textContent = left
      ? `${number(left)} ficaram de fora: pediram para sair da lista ou não têm e-mail`
      : "";
  };

  const element = (tag, text) => Object.assign(document.createElement(tag), { textContent: text });

  const limitExplanation = (audience, data) => {
    const windowMode = data.send_mode === "window";
    const first = audience.first_day_capacity;
    const afterFirst = audience.recipients - first;
    const second = Math.min(audience.daily_limit, afterFirst);
    const steps = [];
    if (first) steps.push(`${audience.first_day_label}: ${number(first)} pessoas`);
    steps.push(`${audience.resume_label}: ${number(second)} pessoas`);
    if (afterFirst > second) {
      const rest = windowMode ? "nos próximos dias da sua janela" : `todos os dias às ${audience.resume_time}`;
      steps.push(`Depois: o restante, até ${number(audience.daily_limit)} por dia, ${rest}`);
    }

    const list = document.createElement("ul");
    list.append(...steps.map((text) => element("li", text)));

    return [
      element("strong", first ? "Passa do seu limite diário" : "Você já usou o limite de hoje"),
      element("p", `Seu plano envia até ${number(audience.daily_limit)} e-mails por dia. Por isso a campanha é enviada em partes, sozinha${windowMode ? `, sempre dentro da sua janela (${data.timing})` : ""}:`),
      list,
      element("p", "Você não precisa fazer nada. Quem pedir para sair no meio do caminho deixa de receber."),
    ];
  };

  const renderSummary = (data) => {
    const audience = data.audience;
    lastData = data;
    reviewButton.disabled = !data.ready;
    renderAudience(data);
    $('[data-summary="cost"]').textContent = audience.cost;
    $('[data-summary="timing"]').textContent = data.timing;
    $('[data-summary="limit"]').textContent = audience.daily_limit
      ? `${number(audience.used_today)} de ${number(audience.daily_limit)} usados`
      : "Sem limite";
    $('[data-summary="limit-left"]').textContent = audience.daily_limit
      ? `restam ${number(Math.max(audience.daily_limit - audience.used_today, 0))} hoje`
      : "";

    const warn = $("#ec-limit-warn");
    const overLimit = audience.daily_limit && audience.timing_ready && audience.recipients > audience.first_day_capacity;
    warn.hidden = !overLimit;
    if (overLimit) warn.replaceChildren(...limitExplanation(audience, data));

    $$("[data-step]", form).forEach((step) => step.classList.toggle("is-done", Boolean(data.steps[step.dataset.step])));

    const list = $("#ec-missing-list");
    list.replaceChildren(...data.missing.map((text) => Object.assign(document.createElement("li"), { textContent: text })));
    $("#ec-missing").hidden = !data.missing.length;

    $("#ec-template-subject").textContent = data.template_subject ? `Assunto: ${data.template_subject}` : "";

    if (String(data.template_id || "") !== currentTemplate) {
      currentTemplate = String(data.template_id || "");
      frame.src = `${form.dataset.previewUrl}?t=${Date.now()}`;
    } else {
      setPreviewLoading(false);
    }
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
    } catch (error) {
      if (error.name === "AbortError") return;

      saving = false;
      failed = true;
      setBusy(false);
      setPreviewLoading(false);
      setStatus("Não foi possível salvar. Tentando de novo ao próximo ajuste.", "error");
    }
  };

  const schedule = (delay = SAVE_DELAY_MS) => {
    pending = true;
    setStatus("Salvando…", "saving");
    clearTimeout(timer);
    timer = setTimeout(save, delay);
  };

  const fitFrame = () => {
    const doc = frame.contentDocument;
    if (!doc?.documentElement) return;

    frame.style.height = "0px";
    frame.style.height = `${doc.documentElement.scrollHeight}px`;
    $$("img", doc).forEach((image) => image.addEventListener("load", fitFrame, { once: true }));
  };

  const setPreviewLoading = (loading) => stage.classList.toggle("is-live-loading", loading);
  const busyAreas = $$(".ec-summary, #ec-audience");
  const setBusy = (busy) => busyAreas.forEach((area) => area.classList.toggle("ec-busy", busy));
  const affectsSummary = (target) => /\[(segment_id|send_mode|scheduled_on|scheduled_time|window_days|window_from|window_to)\]/.test(target.name || "");

  frame.addEventListener("load", () => {
    setPreviewLoading(false);
    fitFrame();
  });

  $$("[data-ec-device]").forEach((button) => {
    button.addEventListener("click", () => {
      $$("[data-ec-device]").forEach((other) => other.classList.toggle("active", other === button));
      stage.classList.toggle("is-mobile", button.dataset.ecDevice === "mobile");
      setTimeout(fitFrame, 50);
    });
  });

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    schedule(0);
  });

  form.addEventListener("input", (event) => {
    if (event.target.id === "ec-test-email") return;

    if (affectsSummary(event.target)) setBusy(true);
    schedule();
  });

  form.addEventListener("change", (event) => {
    if (event.target.matches(".cx-chip input")) event.target.closest(".cx-chip").classList.toggle("is-on", event.target.checked);
    if (event.target.id === "ec-test-email") return;

    if (event.target.name === "campaign[email_template_id]") setPreviewLoading(true);
    if (affectsSummary(event.target)) setBusy(true);

    showModePanel();
    schedule();
  });

  const testButton = $("#ec-test-send");
  const testStatus = $("#ec-test-status");

  const sendTest = async () => {
    const field = $("#ec-test-email");
    testButton.disabled = true;
    testStatus.textContent = "Enviando…";
    testStatus.className = "ec-hint";

    const data = new FormData();
    data.append("test_email", field.value.trim());
    const response = await fetch(testButton.dataset.url, {
      method: "POST", body: data, headers: { Accept: "application/json", "X-CSRF-Token": csrf() },
    }).catch(() => null);
    const result = await response?.json().catch(() => ({}));
    testButton.disabled = false;

    testStatus.textContent = response?.ok ? result.message : result?.error || "Não foi possível enviar o teste.";
    testStatus.className = response?.ok ? "ec-hint ec-hint--ok" : "ec-hint ec-hint--error";
  };

  testButton.addEventListener("click", sendTest);
  $("#ec-test-email").addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    sendTest();
  });

  const dialog = $("#ec-review-dialog");
  const submit = $("#ec-schedule-submit");
  const accept = $("#ec-accept");
  const selectedText = (name) => $(`[name="campaign[${name}]"] option:checked`, form)?.textContent || "";

  const openReview = () => {
    if (!lastData?.ready) return;
    const { audience } = lastData;
    const fill = (key, text) => { $(`[data-review="${key}"]`, dialog).textContent = text; };

    fill("name", form.elements["campaign[name]"].value);
    fill("template", selectedText("email_template_id"));
    fill("segment", selectedText("segment_id"));
    fill("recipients", `${number(audience.recipients)} pessoas`);
    fill("timing", lastData.timing);
    fill("cost", audience.cost);

    const limit = $('[data-review="limit"]', dialog);
    const overLimit = audience.daily_limit && audience.recipients > audience.first_day_capacity;
    limit.hidden = !overLimit;
    if (overLimit) limit.replaceChildren(...limitExplanation(audience, lastData));

    const consent = $("#ec-consent", dialog);
    consent.hidden = !audience.not_subscribed;
    accept.checked = false;
    if (audience.not_subscribed) {
      $('[data-review="consent"]', dialog).textContent =
        `Entendo que ${number(audience.not_subscribed)} pessoas ainda não aceitaram receber promoções e que a responsabilidade por esse envio é da loja.`;
    }
    submit.disabled = Boolean(audience.not_subscribed);
    submit.textContent = lastData.send_mode === "now" ? "Enviar agora" : "Agendar campanha";
    dialog.showModal();
  };

  reviewButton.addEventListener("click", openReview);
  accept.addEventListener("change", () => { submit.disabled = !accept.checked; });
  $("#ec-review-back").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", (event) => { if (event.target === dialog) dialog.close(); });
  $("#ec-schedule-form").addEventListener("submit", () => window.CrmLeaveGuard?.watch(() => false));

  window.CrmLeaveGuard?.watch(() => pending || saving || failed);
  showModePanel();
  save();
})();
