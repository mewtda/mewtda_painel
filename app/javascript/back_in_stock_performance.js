(() => {
  const MAX_ATTEMPTS = 20;
  const brl = (value) => Number(value || 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

  const fail = (element, error) => {
    console.error("Gráfico do De volta ao estoque:", error);
    element.textContent = `Não foi possível carregar o gráfico. (${error?.message || error})`;
    element.classList.add("bp-chart--error");
  };

  const draw = (element) => {
    const style = getComputedStyle(document.documentElement);
    const money = element.dataset.format === "money";
    const labels = JSON.parse(element.dataset.labels);
    const values = JSON.parse(element.dataset.values);
    const format = (value) => (money ? brl(value) : Math.round(value));

    return new window.ApexCharts(element, {
      chart: { type: "area", height: 210, toolbar: { show: false }, fontFamily: "inherit", zoom: { enabled: false } },
      series: [{ name: element.dataset.name, data: values }],
      xaxis: {
        categories: labels,
        tickAmount: Math.min(labels.length - 1, money ? 4 : 6),
        labels: { rotate: 0, hideOverlappingLabels: true, style: { fontSize: "11px" } },
      },
      yaxis: { min: 0, max: values.some((value) => value > 0) ? undefined : 1, forceNiceScale: true, labels: { formatter: format, style: { fontSize: "11px" } } },
      stroke: { curve: "smooth", width: 2 },
      fill: { type: "gradient", gradient: { opacityFrom: 0.35, opacityTo: 0.02 } },
      colors: [style.getPropertyValue("--primary-solid").trim() || "#5800e8"],
      dataLabels: { enabled: false },
      grid: { borderColor: style.getPropertyValue("--outline").trim() || "#ececef" },
      tooltip: { y: { formatter: format } },
    }).render();
  };

  const render = (attempt = 0) => {
    const pending = [...document.querySelectorAll("[data-bis-chart]:not([data-rendered])")];
    if (!pending.length) return;
    if (!window.ApexCharts) {
      if (attempt < MAX_ATTEMPTS) setTimeout(() => render(attempt + 1), 250);
      else pending.forEach((element) => fail(element, "ApexCharts não foi carregado"));
      return;
    }

    pending.forEach((element) => {
      element.dataset.rendered = "true";
      try {
        Promise.resolve(draw(element)).catch((error) => fail(element, error));
      } catch (error) {
        fail(element, error);
      }
    });
  };

  document.addEventListener("DOMContentLoaded", () => render());
  document.addEventListener("live:updated", () => render());
  window.addEventListener("load", () => render());
  render();
})();
