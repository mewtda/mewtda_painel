// Gráficos dos dashboards de Produtos (curva ABC) e Pedidos. Os dados vêm de um <script type="application/json">
// na página; cada gráfico só é desenhado se o elemento dele existir.
(() => {
  const CURVE_COLORS = { A: "#16a34a", B: "#f59e0b", C: "#dc2626" };
  const money = (v) => "R$ " + Number(v || 0).toLocaleString("pt-BR", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const moneyShort = (v) => (Math.abs(v) >= 1000 ? "R$ " + (v / 1000).toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + " mil" : money(v));

  const base = () => {
    const styles = getComputedStyle(document.documentElement);
    return {
      chart: { toolbar: { show: false }, fontFamily: "inherit", foreColor: styles.getPropertyValue("--fg-alt").trim() || "#64748b", zoom: { enabled: false } },
      grid: { borderColor: styles.getPropertyValue("--outline").trim() || "#e5e7eb" },
      dataLabels: { enabled: false },
    };
  };

  const draw = (id, options) => {
    const el = document.getElementById(id);
    if (!el) return;
    const b = base();
    new window.ApexCharts(el, { ...b, ...options, chart: { ...b.chart, ...options.chart } }).render();
  };

  const products = (d) => {
    draw("pa-pareto-chart", {
      chart: { type: "line", height: 320 },
      series: [
        { name: "Faturamento", type: "column", data: d.revenue },
        { name: "Acumulado", type: "line", data: d.cumulative },
      ],
      labels: d.labels,
      // Barra com a cor da curva do produto; a linha do acumulado em cinza-escuro.
      colors: [({ dataPointIndex }) => CURVE_COLORS[d.curves[dataPointIndex]] || "#7c3aed", "#334155"],
      stroke: { width: [0, 3], curve: "smooth" },
      plotOptions: { bar: { borderRadius: 3, columnWidth: "65%" } },
      fill: { opacity: 1 },
      xaxis: { labels: { show: false } },
      yaxis: [
        { labels: { formatter: moneyShort } },
        { opposite: true, min: 0, max: 100, labels: { formatter: (v) => Math.round(v) + "%" } },
      ],
      annotations: { yAxis: [{ y: 80, yAxisIndex: 1, borderColor: CURVE_COLORS.A, strokeDashArray: 4, label: { text: "80%" } }] },
      tooltip: { shared: true, y: [{ formatter: money }, { formatter: (v) => v.toLocaleString("pt-BR", { maximumFractionDigits: 1 }) + "%" }] },
      legend: { position: "top", horizontalAlign: "left" },
    });
    draw("pa-curve-donut", {
      chart: { type: "donut", height: 220 },
      series: d.donut,
      labels: ["Curva A", "Curva B", "Curva C"],
      colors: [CURVE_COLORS.A, CURVE_COLORS.B, CURVE_COLORS.C],
      legend: { position: "bottom" },
      dataLabels: { enabled: true, formatter: (v) => Math.round(v) + "%" },
      tooltip: { y: { formatter: money } },
    });
  };

  const orders = (d) => {
    draw("po-daily-chart", {
      chart: { type: "line", height: 300 },
      series: [
        { name: "Faturamento", type: "area", data: d.revenue },
        { name: "Pedidos", type: "column", data: d.orders },
      ],
      labels: d.labels,
      colors: ["#7c3aed", "#0ea5e9"],
      stroke: { width: [3, 0], curve: "smooth" },
      fill: { type: ["gradient", "solid"], gradient: { opacityFrom: 0.35, opacityTo: 0.02 } },
      plotOptions: { bar: { borderRadius: 3, columnWidth: "55%" } },
      yaxis: [{ labels: { formatter: moneyShort } }, { opposite: true, labels: { formatter: (v) => Math.round(v) } }],
      tooltip: { shared: true, y: [{ formatter: money }, { formatter: (v) => Math.round(v) + " pedidos" }] },
      legend: { position: "top", horizontalAlign: "left" },
    });
    draw("po-hour-chart", {
      chart: { type: "bar", height: 240 },
      series: [{ name: "Pedidos", data: d.hours }],
      xaxis: { categories: d.hour_labels },
      colors: ["#7c3aed"],
      plotOptions: { bar: { borderRadius: 3, columnWidth: "70%" } },
    });
    draw("po-weekday-chart", {
      chart: { type: "bar", height: 240 },
      series: [{ name: "Pedidos", data: d.weekdays }],
      xaxis: { categories: d.weekday_labels },
      colors: ["#0ea5e9"],
      plotOptions: { bar: { borderRadius: 3, columnWidth: "55%" } },
    });
  };

  const start = (attempt = 0) => {
    if (!window.ApexCharts) {
      if (attempt < 20) setTimeout(() => start(attempt + 1), 150);
      return;
    }
    const p = document.getElementById("pa-chart-data");
    if (p) products(JSON.parse(p.textContent));
    const o = document.getElementById("po-chart-data");
    if (o) orders(JSON.parse(o.textContent));
  };

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", () => start());
  else start();
})();
