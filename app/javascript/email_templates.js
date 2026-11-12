(() => {
  const preview = document.getElementById("email-preview");
  const form = document.getElementById("email-template-form");
  if (!preview || !form) return;

  const PREVIEW_DELAY_MS = 300;

  const subject = document.getElementById("email-preview-subject");
  const frame = document.getElementById("email-preview-frame");
  const trigger = document.getElementById("email-field-trigger");
  const layout = document.getElementById("email-field-layout");
  const pendingHint = document.getElementById("email-trigger-pending-hint");
  const AUTOMATED_TRIGGERS = ["back_in_stock"];

  let timer;
  let controller;

  const previewData = () => {
    const data = new FormData(form);
    data.delete("_method");
    data.delete("authenticity_token");
    return data;
  };

  const csrfToken = () => document.querySelector('meta[name="csrf-token"]')?.content;

  const fitFrame = () => {
    frame.style.height = `${frame.contentDocument.documentElement.scrollHeight}px`;
  };

  const refreshPreview = async () => {
    controller?.abort();
    controller = new AbortController();

    const response = await fetch(preview.dataset.url, {
      method: "POST",
      body: previewData(),
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
      signal: controller.signal,
    }).catch(() => null);
    if (!response?.ok) return;

    const email = await response.json();
    subject.textContent = email.subject;
    frame.srcdoc = email.html;
  };

  const schedulePreview = () => {
    clearTimeout(timer);
    timer = setTimeout(refreshPreview, PREVIEW_DELAY_MS);
  };

  const toggleByData = (selector, attribute, current) => {
    document.querySelectorAll(selector).forEach((element) => {
      element.hidden = element.getAttribute(attribute) !== current;
    });
  };

  const hideForTrigger = () => {
    document.querySelectorAll("[data-hide-for]").forEach((element) => {
      element.hidden = element.dataset.hideFor === trigger.value;
    });
  };

  const updateTriggerFields = () => {
    toggleByData(".email-templates-trigger-config", "data-trigger", trigger.value);
    hideForTrigger();
    pendingHint.hidden = AUTOMATED_TRIGGERS.includes(trigger.value);
  };

  const updateLayoutFields = () => toggleByData(".email-templates-layout-config", "data-layout", layout.value);

  frame.addEventListener("load", fitFrame);
  form.addEventListener("input", schedulePreview);
  form.addEventListener("change", schedulePreview);
  trigger.addEventListener("change", updateTriggerFields);
  layout.addEventListener("change", updateLayoutFields);

  updateTriggerFields();
  updateLayoutFields();
  refreshPreview();
})();
