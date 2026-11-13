// Clientes: seleção em massa e painel lateral de detalhes.
(() => {
  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => Array.from(root.querySelectorAll(s));
  const brl = (v) => Number(v || 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });
  const el = (tag, cls, text) => {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined && text !== null) node.textContent = text;
    return node;
  };

  // ---------------------------------------------------- seleção em massa --
  const allFiltered = () => $("#cx-all-filtered");
  const updateBulk = () => {
    const bulk = $("#cx-bulk-form");
    if (!bulk) return;
    const checked = $$(".cx-row-check:checked").length;
    const all = allFiltered().value === "1";
    bulk.hidden = !checked && !all;
    $("#cx-bulk-count").textContent = all ? "Todos os clientes do filtro selecionados" : `${checked} selecionado(s)`;
  };
  document.addEventListener("change", (e) => {
    if (e.target.matches("#cx-check-all")) {
      $$(".cx-row-check").forEach((c) => { c.checked = e.target.checked; });
      allFiltered().value = "0";
      updateBulk();
    } else if (e.target.matches(".cx-row-check")) {
      allFiltered().value = "0";
      updateBulk();
    }
  });
  document.addEventListener("click", (e) => {
    if (!e.target.closest("#cx-select-all-filtered")) return;
    allFiltered().value = "1";
    $$(".cx-row-check").forEach((c) => { c.checked = true; });
    updateBulk();
  });

  // ------------------------------------------------------------- drawer --
  const drawer = $("#cx-drawer");
  const overlay = $("#cx-drawer-overlay");
  if (!drawer) return;
  const field = (name) => $(`[data-field="${name}"]`, drawer);

  const close = () => {
    drawer.classList.remove("is-open");
    drawer.setAttribute("aria-hidden", "true");
    overlay.hidden = true;
  };

  const renderOrders = (orders, store) => {
    const box = $("[data-orders]", drawer);
    box.replaceChildren();
    if (!orders.length) { box.appendChild(el("p", "cx-muted", "Nenhum pedido.")); return; }
    orders.forEach((order) => {
      const card = el("details", "cx-order");
      const summary = el("summary", "cx-order__head");
      const number = el("a", "cx-order__number", order.number || "—");
      if (store && order.shopify_id) {
        number.href = `https://admin.shopify.com/store/${encodeURIComponent(store)}/orders/${encodeURIComponent(order.shopify_id)}`;
        number.target = "_blank";
        number.rel = "noopener";
      }
      summary.append(number, el("span", "cx-muted", order.date || "—"), el("span", "cx-muted", `${order.items_count} item(s)`));
      if (order.coupon) summary.append(el("span", "crm-tag crm-tag--warning", order.coupon));
      summary.append(el("strong", "cx-order__total", brl(order.total)));
      card.appendChild(summary);
      (order.items || []).forEach((item) => {
        const row = el("div", "cx-order__item");
        if (item.image) {
          const img = el("img");
          img.src = item.image;
          img.alt = "";
          img.loading = "lazy";
          row.appendChild(img);
        } else {
          row.appendChild(el("span", "cx-order__noimg"));
        }
        const info = el("div", "cx-order__info");
        info.append(el("div", null, item.name || "—"), el("small", "cx-muted", item.sku || ""));
        row.append(info, el("span", "cx-muted", `x${item.qty}`), el("span", null, brl(item.price * item.qty)));
        card.appendChild(row);
      });
      box.appendChild(card);
    });
  };

  const open = async (id) => {
    drawer.classList.add("is-open");
    drawer.setAttribute("aria-hidden", "false");
    overlay.hidden = false;
    const loading = $("[data-loading]", drawer);
    loading.hidden = false;
    loading.textContent = "Carregando…";
    $("[data-content]", drawer).hidden = true;
    field("name").textContent = "";
    field("rfm").replaceChildren();
    try {
      const response = await fetch(`/crm/customers/${encodeURIComponent(id)}/details`, { headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error("load");
      const { customer: c, orders, shopify_store: store } = await response.json();
      field("initials").textContent = (c.name || "?").split(/\s+/).slice(0, 2).map((w) => w[0] || "").join("").toUpperCase();
      field("name").textContent = c.name || "Sem nome";
      if (c.rfm) {
        const tag = el("span", "rfm-tag", c.rfm);
        tag.style.setProperty("--rfm", c.rfm_color);
        field("rfm").appendChild(tag);
      }
      field("rfm_hint").textContent = c.rfm_hint || "";
      field("total_spent").textContent = brl(c.total_spent);
      field("orders_count").textContent = c.orders_count;
      field("avg_ticket").textContent = brl(c.avg_ticket);
      field("last_order_at").textContent = c.last_order_at || "—";
      field("days_since").textContent = c.days_since != null ? `há ${c.days_since} dias` : "";
      field("email").textContent = c.email || "—";
      field("phone").textContent = c.phone || "—";
      field("city").textContent = c.city || "—";
      field("first_order_at").textContent = c.first_order_at || "—";
      field("lists").textContent = (c.lists || []).join(", ") || "—";
      renderOrders(orders || [], store);
      loading.hidden = true;
      $("[data-content]", drawer).hidden = false;
    } catch (error) {
      loading.textContent = "Não foi possível carregar o cliente.";
    }
  };

  document.addEventListener("click", (e) => {
    const row = e.target.closest(".cx-row");
    if (row && !e.target.closest("input, a, button")) open(row.dataset.customerId);
    if (e.target.closest("[data-close]") || e.target === overlay) close();
  });
  document.addEventListener("keydown", (e) => { if (e.key === "Escape") close(); });
})();
