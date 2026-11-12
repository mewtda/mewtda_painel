(() => {
  const COPIED_FEEDBACK_MS = 1500;

  const copy = async (button) => {
    const icon = button.querySelector("i");

    await navigator.clipboard.writeText(button.dataset.copyValue);
    button.classList.add("is-copied");
    icon.className = "fa-solid fa-check";

    setTimeout(() => {
      button.classList.remove("is-copied");
      icon.className = "fa-solid fa-copy";
    }, COPIED_FEEDBACK_MS);
  };

  document.querySelectorAll("[data-copy-value]").forEach((button) => {
    button.addEventListener("click", () => copy(button));
  });
})();
