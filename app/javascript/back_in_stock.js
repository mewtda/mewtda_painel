(() => {
  const root = document.getElementById("bis-screen");
  if (!root) return;

  const tabs = root.querySelectorAll("[data-tab]");
  const panels = root.querySelectorAll("[data-panel]");
  const copyButton = root.querySelector("[data-copy]");
  const sortSelect = root.querySelector("form[data-autosubmit] select");
  const chartElement = root.querySelector("[data-summary-chart]");
  let chartRendered = false;

  const panelExists = (key) => [...panels].some((panel) => panel.dataset.panel === key);

  const renderChart = () => {
    if (!chartElement || chartRendered) return;

    chartRendered = true;
    const style = getComputedStyle(document.documentElement);

    new ApexCharts(chartElement, {
      chart: { type: "bar", height: 260, toolbar: { show: false }, fontFamily: "inherit" },
      series: [{ name: "E-mails enviados", data: JSON.parse(chartElement.dataset.values) }],
      xaxis: { categories: JSON.parse(chartElement.dataset.labels) },
      yaxis: { min: 0, forceNiceScale: true, labels: { formatter: (value) => Math.round(value) } },
      colors: [style.getPropertyValue("--primary").trim()],
      plotOptions: { bar: { borderRadius: 4, columnWidth: "45%" } },
      dataLabels: { enabled: false },
      grid: { borderColor: style.getPropertyValue("--outline").trim() },
      tooltip: { theme: "light" },
    }).render();
  };

  const showTab = (key) => {
    const current = panelExists(key) ? key : tabs[0].dataset.tab;

    tabs.forEach((tab) => {
      const active = tab.dataset.tab === current;
      tab.classList.toggle("is-active", active);
      tab.setAttribute("aria-selected", active);
    });

    panels.forEach((panel) => (panel.hidden = panel.dataset.panel !== current));
    history.replaceState(null, "", `#${current}`);
    if (current === "resumo") renderChart();
  };

  const copySnippet = async () => {
    const label = copyButton.querySelector("span");
    const snippet = root.querySelector("[data-snippet]").textContent.trim();

    await navigator.clipboard.writeText(snippet);
    label.textContent = "Copiado!";
    setTimeout(() => (label.textContent = "Copiar script"), 2000);
  };

  tabs.forEach((tab) => tab.addEventListener("click", () => showTab(tab.dataset.tab)));
  copyButton.addEventListener("click", copySnippet);
  sortSelect?.addEventListener("change", () => sortSelect.form.requestSubmit());

  document.addEventListener("click", (event) => {
    const open = root.querySelector(".bis-filter[open]");
    if (open && event.target.isConnected && !open.contains(event.target)) open.removeAttribute("open");
  });
  document.addEventListener("click", (event) => {
    const button = event.target.closest("[data-clear-filters]");
    if (!button) return;

    const panel = button.closest(".bis-filter__panel");
    panel.querySelectorAll("input[type=checkbox]").forEach((box) => { box.checked = false; });
    panel.querySelectorAll("input:not([type=checkbox])").forEach((input) => { input.value = ""; });
    panel.querySelectorAll("select").forEach((select) => {
      select.selectedIndex = 0;
      select.dispatchEvent(new Event("change", { bubbles: true }));
    });
    button.form.requestSubmit();
  });

  document.addEventListener("submit", (event) => {
    if (event.target.matches(".bis-toolbar")) root.querySelector(".bis-filter[open]")?.removeAttribute("open");
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") root.querySelector(".bis-filter[open]")?.removeAttribute("open");
  });

  showTab(location.hash.slice(1));
})();
