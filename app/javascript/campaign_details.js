(() => {
  const dialog = document.getElementById("ec-details-dialog");
  if (!dialog) return;

  const body = dialog.querySelector("[data-details-body]");
  let request = 0;

  const show = (html) => {
    body.innerHTML = html;
    const testForm = body.querySelector("[data-campaign-test]");
    if (testForm) syncTestField(testForm);
  };
  const message = (text, loading = false) => {
    const paragraph = document.createElement("p");
    paragraph.className = "ec-details__message";
    if (loading) {
      const icon = document.createElement("i");
      icon.className = "fa-solid fa-circle-notch fa-spin";
      paragraph.append(icon, " ");
    }
    paragraph.append(text);
    body.replaceChildren(paragraph);
  };

  const open = async (url) => {
    const current = ++request;
    message("Carregando…", true);
    if (!dialog.open) dialog.showModal();
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } });
      if (!response.ok) throw new Error("load");
      const html = await response.text();
      if (current === request) show(html);
    } catch (error) {
      if (current === request) message("Não foi possível carregar os detalhes.");
    }
  };

  const close = () => {
    if (!dialog.open || dialog.classList.contains("is-closing")) return;
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced) return dialog.close();
    dialog.classList.add("is-closing");
    const done = (event) => {
      if (event.target !== dialog) return;
      dialog.removeEventListener("animationend", done);
      dialog.classList.remove("is-closing");
      dialog.close();
    };
    dialog.addEventListener("animationend", done);
  };

  dialog.addEventListener("cancel", (event) => {
    event.preventDefault();
    close();
  });

  // ---------- Enviar um teste ----------
  // O último e-mail e o último celular usados ficam salvos no navegador e voltam preenchidos.
  const TEST_KEYS = { email: "campaignTestEmail", whatsapp: "campaignTestPhone" };
  const remembered = (channel) => { try { return localStorage.getItem(TEST_KEYS[channel]) || ""; } catch { return ""; } };
  const remember = (channel, value) => { try { localStorage.setItem(TEST_KEYS[channel], value); } catch { /* sem storage */ } };

  const selectedOption = (form) => form.querySelector("[data-test-message]").selectedOptions[0];

  const syncTestField = (form) => {
    const channel = selectedOption(form).dataset.channel;
    const input = form.querySelector("[data-test-address]");
    const whatsapp = channel === "whatsapp";
    input.type = whatsapp ? "tel" : "email";
    input.placeholder = whatsapp ? "(31) 99999-9999" : "seu@email.com";
    input.value = remembered(channel);
    form.querySelector("[data-test-status]").textContent = "";
  };

  const sendTest = async (form) => {
    const option = selectedOption(form);
    const channel = option.dataset.channel;
    const address = form.querySelector("[data-test-address]").value.trim();
    const status = form.querySelector("[data-test-status]");
    const button = form.querySelector("button[type=submit]");
    const data = new FormData();
    if (channel === "whatsapp") {
      data.append("phone", address);
      data.append("whatsapp_template_id", option.dataset.templateId || "");
    } else {
      data.append("test_email", address);
      data.append("message_id", option.value);
    }
    button.disabled = true;
    status.className = "ec-hint";
    status.textContent = "Enviando…";
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content || "";
    const response = await fetch(option.dataset.url, {
      method: "POST", body: data, headers: { Accept: "application/json", "X-CSRF-Token": csrf },
    }).catch(() => null);
    const result = await response?.json().catch(() => ({}));
    button.disabled = false;
    if (response?.ok) remember(channel, address);
    status.textContent = response?.ok ? result.message : result?.error || "Não foi possível enviar o teste.";
    status.className = response?.ok ? "ec-hint ec-hint--ok" : "ec-hint ec-hint--error";
  };

  dialog.addEventListener("change", (event) => {
    if (event.target.matches("[data-test-message]")) syncTestField(event.target.closest("[data-campaign-test]"));
  });

  dialog.addEventListener("submit", (event) => {
    const form = event.target.closest("[data-campaign-test]");
    if (!form) return;
    event.preventDefault();
    sendTest(form);
  });

  document.addEventListener("click", (event) => {
    const trigger = event.target.closest("[data-campaign-details]");
    if (trigger) {
      event.preventDefault();
      open(trigger.dataset.campaignDetails);
      return;
    }
    if (event.target.closest("[data-details-close]") || event.target === dialog) close();
  });
})();
