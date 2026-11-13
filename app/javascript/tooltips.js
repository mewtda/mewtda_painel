(() => {
  document.addEventListener("DOMContentLoaded", () => {
    if (!window.bootstrap?.Tooltip) return;

    new window.bootstrap.Tooltip(document.body, { selector: "[title]", trigger: "hover", placement: "top", container: "body" });
  });
})();
