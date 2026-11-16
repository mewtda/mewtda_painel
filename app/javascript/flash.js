(() => {
  const VISIBLE_MS = 5000;
  const FADE_MS = 300;

  const dismiss = (alert) => {
    alert.classList.add("is-leaving");
    setTimeout(() => alert.remove(), FADE_MS);
  };

  const watch = (alert) => {
    let timer = setTimeout(() => dismiss(alert), VISIBLE_MS);
    alert.addEventListener("mouseenter", () => clearTimeout(timer));
    alert.addEventListener("mouseleave", () => { timer = setTimeout(() => dismiss(alert), VISIBLE_MS / 2); });
  };

  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll(".crm-alert--success").forEach(watch);
  });
})();
