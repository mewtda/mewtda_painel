(() => {
  document.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-copy-text]");
    if (!button) return;

    const label = button.querySelector("span");
    await navigator.clipboard.writeText(button.dataset.copyText);
    label.textContent = "Copiado!";
    setTimeout(() => { label.textContent = "Copiar"; }, 2000);
  });
})();
