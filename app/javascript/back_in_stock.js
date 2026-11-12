(() => {
  const root = document.getElementById("bis-screen");
  if (!root) return;

  const tabs = root.querySelectorAll("[data-tab]");
  const panels = root.querySelectorAll("[data-panel]");
  const copyButton = root.querySelector("[data-copy]");
  const confirmForms = root.querySelectorAll("form[data-confirm]");
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

  const confirmSubmit = (event) => {
    if (!confirm(event.currentTarget.dataset.confirm)) event.preventDefault();
  };

  tabs.forEach((tab) => tab.addEventListener("click", () => showTab(tab.dataset.tab)));
  copyButton.addEventListener("click", copySnippet);
  confirmForms.forEach((form) => form.addEventListener("submit", confirmSubmit));
  sortSelect?.addEventListener("change", () => sortSelect.form.requestSubmit());

  showTab(location.hash.slice(1));
})();
