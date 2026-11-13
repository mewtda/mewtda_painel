// Construtor de segmentos: grupos (OU) de condições (E), com contagem ao vivo.
(() => {
  const builder = document.getElementById("sg-builder");
  if (!builder) return;

  const $ = (s, root = document) => root.querySelector(s);
  const schema = JSON.parse($("#sg-schema").textContent);
  const rulesInput = $("#sg-rules");
  const fields = Object.fromEntries(schema.fields.map((f) => [f.key, f]));
  const csrf = () => $('meta[name="csrf-token"]')?.content;

  let state;
  try {
    state = JSON.parse(rulesInput.value || "{}");
  } catch (error) {
    state = {};
  }
  if (!Array.isArray(state.groups) || !state.groups.length) state = { groups: [{ conditions: [{}] }] };

  const el = (tag, attrs = {}, children = []) => {
    const node = document.createElement(tag);
    Object.entries(attrs).forEach(([k, v]) => {
      if (k === "class") node.className = v;
      else if (k === "text") node.textContent = v;
      else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
      else if (v !== undefined && v !== null && v !== false) node.setAttribute(k, v === true ? "" : v);
    });
    children.forEach((c) => c && node.appendChild(c));
    return node;
  };

  const option = (value, label, selected) => {
    const o = el("option", { value, text: label });
    o.selected = selected;
    return o;
  };

  const sync = () => {
    rulesInput.value = JSON.stringify(state);
    schedulePreview();
  };

  // ---------------------------------------------------------- campos --
  const fieldSelect = (cond, onChange) => {
    const select = el("select", { class: "crm-input sg-field", "aria-label": "Critério" });
    select.appendChild(option("", "Selecione o critério…", !cond.field));
    const groups = {};
    schema.fields.forEach((f) => {
      groups[f.group] ||= el("optgroup", { label: f.group });
      groups[f.group].appendChild(option(f.key, f.label, cond.field === f.key));
    });
    Object.values(groups).forEach((g) => select.appendChild(g));
    select.addEventListener("change", () => onChange(select.value));
    return select;
  };

  const opSelect = (cond, type) => {
    const select = el("select", { class: "crm-input sg-op", "aria-label": "Operador" });
    schema.ops[type].forEach((op) => select.appendChild(option(op.key, op.label, cond.op === op.key)));
    if (!cond.op) cond.op = schema.ops[type][0].key;
    select.addEventListener("change", () => {
      cond.op = select.value;
      render();
      sync();
    });
    return select;
  };

  const input = (cond, key, attrs) => {
    const node = el("input", { class: "crm-input sg-value", ...attrs });
    node.value = cond[key] || "";
    node.addEventListener("input", () => {
      cond[key] = node.value;
      sync();
    });
    return node;
  };

  const valueControls = (cond, type) => {
    const op = cond.op;
    if (type === "bool") return [];
    if (type === "rfm" || type === "marketing") {
      const chosen = new Set(Array.isArray(cond.value) ? cond.value : []);
      const box = el("div", { class: "sg-rfm" });
      schema[type].forEach((r) => {
        const cb = el("input", { type: "checkbox", value: r.key });
        cb.checked = chosen.has(r.key);
        cb.addEventListener("change", () => {
          if (cb.checked) chosen.add(r.key);
          else chosen.delete(r.key);
          cond.value = Array.from(chosen);
          label.classList.toggle("is-on", cb.checked);
          sync();
        });
        const label = el("label", { class: `cx-chip ${cb.checked ? "is-on" : ""}` }, [cb, document.createTextNode(r.label)]);
        box.appendChild(label);
      });
      return [box];
    }
    if (type === "segment") {
      const select = el("select", { class: "crm-input sg-value" });
      select.appendChild(option("", "Escolha…", !cond.value));
      schema.segments.forEach((s) => select.appendChild(option(String(s.id), s.name, String(cond.value) === String(s.id))));
      select.addEventListener("change", () => {
        cond.value = select.value;
        sync();
      });
      return [select];
    }
    if (type === "date") {
      if (op === "last_days" || op === "more_than_days") {
        return [input(cond, "value", { type: "number", min: 1, placeholder: "dias" }), el("span", { class: "cx-muted", text: "dias" })];
      }
      const controls = [input(cond, "value", { type: "date" })];
      if (op === "between") controls.push(el("span", { class: "cx-muted", text: "e" }), input(cond, "value2", { type: "date" }));
      return controls;
    }
    const numeric = type === "number" || type === "money";
    const attrs = numeric ? { type: "number", step: type === "money" ? "0.01" : "1", min: 0, placeholder: type === "money" ? "R$" : "0" } : { type: "text", placeholder: "Digite…" };
    const controls = [input(cond, "value", attrs)];
    if (numeric && op === "between") controls.push(el("span", { class: "cx-muted", text: "e" }), input(cond, "value2", attrs));
    return controls;
  };

  // ------------------------------------------------------------ render --
  const groupsBox = $("#sg-groups");

  const render = () => {
    groupsBox.replaceChildren();
    state.groups.forEach((group, gi) => {
      if (gi > 0) groupsBox.appendChild(el("div", { class: "sg-or", text: "OU" }));
      const card = el("div", { class: "crm-card sg-group" });
      const head = el("div", { class: "sg-group__head" }, [el("span", { class: "sg-group__label", text: `Grupo ${gi + 1}` })]);
      if (state.groups.length > 1) {
        head.appendChild(el("button", {
          type: "button", class: "cx-icon-btn", title: "Remover grupo",
          onclick: () => { state.groups.splice(gi, 1); render(); sync(); },
        }, [el("i", { class: "fa-solid fa-trash-can" })]));
      }
      card.appendChild(head);

      group.conditions.forEach((cond, ci) => {
        if (ci > 0) card.appendChild(el("div", { class: "sg-and", text: "E" }));
        const row = el("div", { class: "sg-cond" });
        row.appendChild(fieldSelect(cond, (key) => {
          group.conditions[ci] = { field: key };
          render();
          sync();
        }));
        const field = fields[cond.field];
        if (field) {
          row.appendChild(opSelect(cond, field.type));
          valueControls(cond, field.type).forEach((c) => row.appendChild(c));
        } else {
          row.appendChild(el("span", { class: "sg-tip", text: "💡 Primeiro selecione o critério para iniciar a segmentação." }));
        }
        row.appendChild(el("button", {
          type: "button", class: "cx-icon-btn sg-cond__remove", title: "Remover condição",
          onclick: () => {
            group.conditions.splice(ci, 1);
            if (!group.conditions.length) group.conditions.push({});
            render();
            sync();
          },
        }, [el("i", { class: "fa-solid fa-xmark" })]));
        card.appendChild(row);
      });

      card.appendChild(el("button", {
        type: "button", class: "crm-btn crm-btn--primary sg-add-cond",
        onclick: () => { group.conditions.push({}); render(); },
      }, [el("i", { class: "fa-solid fa-plus" }), document.createTextNode(" Adicionar condição")]));
      groupsBox.appendChild(card);
    });
  };

  $("#sg-add-group").addEventListener("click", () => {
    state.groups.push({ conditions: [{}] });
    render();
  });

  // ----------------------------------------------------------- preview --
  let timer;
  let controller;
  const brl = (v) => Number(v || 0).toLocaleString("pt-BR", { style: "currency", currency: "BRL" });

  const preview = async () => {
    controller?.abort();
    controller = new AbortController();
    $("#sg-count").classList.add("is-loading");
    const body = new FormData();
    body.append("rules_json", rulesInput.value);
    try {
      const response = await fetch(builder.dataset.previewUrl, {
        method: "POST", body, signal: controller.signal,
        headers: { Accept: "application/json", "X-CSRF-Token": csrf() },
      });
      if (!response.ok) return;
      const data = await response.json();
      $("#sg-count").textContent = data.count.toLocaleString("pt-BR");
      $("#sg-percent").textContent = `Representando ${String(data.percent).replace(".", ",")}% da sua base`;
      $("#sg-bar").style.width = `${Math.min(data.percent, 100)}%`;
      $("#sg-subscribed").textContent = `${data.subscribed.toLocaleString("pt-BR")} inscritos em e-mail marketing`;
      const sample = $("#sg-sample");
      sample.replaceChildren();
      if (data.sample.length) {
        sample.appendChild(el("div", { class: "cx-muted", text: "Maiores clientes do segmento:" }));
        data.sample.forEach((s) => sample.appendChild(el("div", { class: "sg-sample-row" }, [
          el("span", { text: s.name || "Sem nome" }), el("strong", { text: brl(s.spent) }),
        ])));
      }
    } catch (error) {
      // requisição cancelada por outra mais nova
    } finally {
      $("#sg-count").classList.remove("is-loading");
    }
  };

  function schedulePreview() {
    clearTimeout(timer);
    timer = setTimeout(preview, 450);
  }

  render();
  rulesInput.value = JSON.stringify(state);
  preview();
})();
