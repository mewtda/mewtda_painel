(() => {
  let dialog;
  let resolveAnswer;

  const build = () => {
    dialog = document.createElement("dialog");
    dialog.className = "crm-confirm";
    dialog.innerHTML = `
      <div class="crm-confirm__icon"><i class="fa-solid fa-triangle-exclamation"></i></div>
      <h2 class="crm-confirm__title"></h2>
      <p class="crm-confirm__message"></p>
      <div class="crm-confirm__actions">
        <button type="button" class="crm-btn crm-btn--secondary" data-cancel></button>
        <button type="button" class="crm-btn crm-btn--danger" data-accept></button>
      </div>
    `;

    dialog.addEventListener("click", (event) => {
      if (event.target === dialog || event.target.closest("[data-cancel]")) dialog.close();
    });
    dialog.querySelector("[data-accept]").addEventListener("click", () => dialog.close("accept"));
    dialog.addEventListener("close", () => resolveAnswer?.(dialog.returnValue === "accept"));

    document.body.append(dialog);
  };

  const ask = ({ title = "Tem certeza?", message, confirmLabel = "Confirmar", cancelLabel = "Cancelar" }) => {
    if (!dialog) build();

    dialog.querySelector(".crm-confirm__title").textContent = title;
    dialog.querySelector(".crm-confirm__message").textContent = message;
    dialog.querySelector("[data-accept]").textContent = confirmLabel;
    dialog.querySelector("[data-cancel]").textContent = cancelLabel;
    dialog.returnValue = "";
    dialog.showModal();

    return new Promise((resolve) => {
      resolveAnswer = resolve;
    });
  };

  window.CrmConfirm = { ask };

  document.addEventListener("submit", async (event) => {
    const form = event.target;
    if (!form.dataset?.confirm) return;

    event.preventDefault();
    if (await ask({ message: form.dataset.confirm, confirmLabel: form.dataset.confirmLabel, cancelLabel: form.dataset.confirmCancelLabel })) form.submit();
  });
})();
