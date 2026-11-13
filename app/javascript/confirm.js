(() => {
  let dialog;
  let pendingForm;

  const build = () => {
    dialog = document.createElement("dialog");
    dialog.className = "crm-confirm";
    dialog.innerHTML = `
      <div class="crm-confirm__icon"><i class="fa-solid fa-triangle-exclamation"></i></div>
      <h2 class="crm-confirm__title">Tem certeza?</h2>
      <p class="crm-confirm__message"></p>
      <div class="crm-confirm__actions">
        <button type="button" class="crm-btn crm-btn--secondary" data-cancel>Cancelar</button>
        <button type="button" class="crm-btn crm-btn--danger" data-accept></button>
      </div>
    `;

    dialog.addEventListener("click", (event) => {
      if (event.target === dialog || event.target.closest("[data-cancel]")) dialog.close();
    });
    dialog.querySelector("[data-accept]").addEventListener("click", () => {
      const form = pendingForm;
      dialog.close();
      form.submit();
    });

    document.body.append(dialog);
  };

  const open = (form) => {
    if (!dialog) build();

    pendingForm = form;
    dialog.querySelector(".crm-confirm__message").textContent = form.dataset.confirm;
    dialog.querySelector("[data-accept]").textContent = form.dataset.confirmLabel || "Confirmar";
    dialog.showModal();
  };

  document.addEventListener("submit", (event) => {
    if (!event.target.dataset?.confirm) return;

    event.preventDefault();
    open(event.target);
  });
})();
