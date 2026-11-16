(() => {
  const hideAll = () => {
    document.querySelectorAll("[data-bs-original-title]").forEach((element) => {
      window.bootstrap.Tooltip.getInstance(element)?.hide();
    });
    document.querySelectorAll(".tooltip").forEach((tooltip) => tooltip.remove());
  };

  document.addEventListener("DOMContentLoaded", () => {
    if (!window.bootstrap?.Tooltip) return;

    new window.bootstrap.Tooltip(document.body, { selector: "[title]", trigger: "hover", placement: "top", container: "body", animation: false, delay: 0, offset: [0, 8] });
    document.addEventListener("click", hideAll, true);
  });
})();
