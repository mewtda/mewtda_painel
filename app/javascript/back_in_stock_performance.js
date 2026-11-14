(() => {
  const brl = (value) => Number(value || 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

  const render = () => {
    if (!window.ApexCharts) return;

    const style = getComputedStyle(document.documentElement);
    const color = style.getPropertyValue("--primary-solid").trim() || style.getPropertyValue("--primary").trim();
    const grid = style.getPropertyValue("--outline").trim();
    const text = style.getPropertyValue("--fg-alt").trim();

    document.querySelectorAll("[data-bis-chart]").forEach((element) => {
      if (element.dataset.rendered) return;

      element.dataset.rendered = "true";
      const money = element.dataset.format === "money";
      const labels = JSON.parse(element.dataset.labels);

      new window.ApexCharts(element, {
        chart: { type: "area", height: 210, toolbar: { show: false }, fontFamily: "inherit", zoom: { enabled: false } },
        series: [{ name: element.dataset.name, data: JSON.parse(element.dataset.values) }],
        xaxis: { categories: labels, tickAmount: Math.min(labels.length - 1, 6), labels: { rotate: 0, style: { colors: text } }, tooltip: { enabled: false } },
        yaxis: { min: 0, forceNiceScale: true, labels: { style: { colors: text }, formatter: (value) => (money ? brl(value) : Math.round(value)) } },
        stroke: { curve: "smooth", width: 2 },
        fill: { type: "gradient", gradient: { opacityFrom: 0.35, opacityTo: 0.02 } },
        colors: [color],
        dataLabels: { enabled: false },
        grid: { borderColor: grid },
        tooltip: { y: { formatter: (value) => (money ? brl(value) : Math.round(value)) } },
        noData: { text: "Sem dados" },
      }).render();
    });
  };

  document.addEventListener("DOMContentLoaded", render);
  document.addEventListener("live:updated", render);
  if (document.readyState !== "loading") render();
})();
