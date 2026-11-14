(() => {
  const panel = () => document.querySelector(".cp-period[open]");

  document.addEventListener("submit", (event) => {
    if (event.target.matches(".cp-filters")) panel()?.removeAttribute("open");
  });

  document.addEventListener("click", (event) => {
    const open = panel();
    if (open && !open.contains(event.target)) open.removeAttribute("open");
  });

  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") panel()?.removeAttribute("open");
  });
})();
