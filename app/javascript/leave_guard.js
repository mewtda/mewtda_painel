(() => {
  let isDirty = () => false;

  const confirmLeave = (title, confirmLabel) =>
    window.CrmConfirm.ask({
      title,
      message: "Você tem alterações que ainda não foram salvas. Se continuar, elas serão perdidas.",
      confirmLabel,
      cancelLabel: "Continuar editando",
    });

  window.CrmLeaveGuard = { watch: (callback) => { isDirty = callback; } };

  window.addEventListener("beforeunload", (event) => {
    if (!isDirty()) return;
    event.preventDefault();
    event.returnValue = "";
  });

  document.addEventListener("click", async (event) => {
    const link = event.target.closest?.("a[href]");
    const modified = event.metaKey || event.ctrlKey || event.shiftKey || event.altKey;
    if (!isDirty() || !link || !window.CrmConfirm || link.target === "_blank" || event.defaultPrevented || modified) return;

    const url = new URL(link.href, location.href);
    if (url.origin !== location.origin || (url.pathname === location.pathname && url.hash)) return;

    event.preventDefault();
    if (!(await confirmLeave("Sair sem salvar?", "Sair sem salvar"))) return;

    window.CrmLeaveGuard.watch(() => false);
    location.href = link.href;
  });

  document.addEventListener("keydown", async (event) => {
    const reload = event.key === "F5" || ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "r");
    if (!reload || !isDirty() || !window.CrmConfirm) return;

    event.preventDefault();
    if (!(await confirmLeave("Atualizar a página?", "Atualizar sem salvar"))) return;

    window.CrmLeaveGuard.watch(() => false);
    location.reload();
  });
})();
