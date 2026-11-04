// Gestão dos números do WhatsApp (Evolution Mewtda) na edição do cliente.
(() => {
  const section = document.getElementById("wan-section");
  const cardsRoot = document.getElementById("wan-cards");
  if (!section || !cardsRoot) return;

  const base = section.dataset.base;
  const notice = document.getElementById("wan-notice");
  const status = document.getElementById("wan-status");
  const provider = document.getElementById("client_whatsapp_provider");
  const labels = {
    connected: "Conectado",
    connecting: "Conectando",
    qr: "Aguardando leitura do QR",
    disconnected: "Desconectado",
    disconnecting: "Desconectando",
  };
  let users = [];
  let timers = [];

  const el = (tag, text, cls) => {
    const node = document.createElement(tag);
    if (text !== undefined) node.textContent = text;
    if (cls) node.className = cls;
    return node;
  };
  const csrf = () =>
    document.querySelector('meta[name="csrf-token"]')?.content || "";
  const say = (message) => {
    notice.textContent = message || "";
    notice.hidden = !message;
  };
  async function api(path, method = "GET", body) {
    const response = await fetch(`${base}${path}`, {
      method,
      credentials: "same-origin",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": csrf(),
        ...(body ? { "Content-Type": "application/json" } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    const data = response.status === 204 ? {} : await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error || "Não foi possível concluir a ação.");
    return data;
  }
  const guard = (fn) => async (...args) => {
    try {
      say("");
      await fn(...args);
    } catch (error) {
      say(error.message);
    }
  };

  function userChecks(selected = []) {
    const wrap = el("div");
    if (!users.length) {
      wrap.append(el("small", "Este cliente ainda não tem usuários. Administradores veem todos os números."));
      return wrap;
    }
    users.forEach((u) => {
      const label = el("label");
      const input = document.createElement("input");
      input.type = "checkbox"; // sem name: não vai junto com o form do cliente
      input.value = u.id;
      input.checked = selected.includes(u.id);
      label.append(input, ` ${u.name}`);
      wrap.append(label);
    });
    return wrap;
  }
  const checked = (root) =>
    Array.from(root.querySelectorAll("input:checked")).map((i) => i.value);

  function renderCard(c) {
    const card = el("article", undefined, `wan-card is-${c.state}`);
    const head = el("div", undefined, "wan-card__head");
    head.append(el("h4", c.name), el("span", labels[c.state] || c.state, "wan-card__state"));
    card.append(head, el("small", c.phone || "Telefone ainda não confirmado pelo WhatsApp"));

    if (c.qr && c.qr_expires_at && new Date(c.qr_expires_at) > new Date()) {
      const frame = el("div", undefined, "wan-card__qr");
      const img = el("img");
      img.src = c.qr;
      img.alt = `QR para conectar ${c.name}`;
      frame.append(img, el("small", "WhatsApp Business → Aparelhos conectados → Conectar aparelho. O QR é temporário."));
      card.append(frame);
      timers.push(setTimeout(() => frame.remove(), Math.max(0, new Date(c.qr_expires_at) - Date.now())));
    }
    if (c.error_code)
      card.append(el("p", "Não foi possível concluir a comunicação. Verifique o serviço e tente conectar novamente.", "wan-card__warn"));

    const actions = el("div", undefined, "wan-card__actions");
    const button = (text, run) => {
      const b = el("button", text, "crm-btn crm-btn--secondary");
      b.type = "button";
      b.onclick = guard(async () => {
        b.disabled = true;
        try { await run(); } finally { b.disabled = false; }
        await refresh();
      });
      actions.append(b);
    };
    button(c.state === "connected" ? "Reconectar" : "Conectar / renovar QR", () => api(`/${c.id}/connect`, "POST", {}));
    button("Sincronizar", () => api(`/${c.id}/sync`, "POST", {}));
    button("Desconectar", async () => {
      if (confirm(`Desconectar ${c.name}? O histórico será mantido.`)) await api(`/${c.id}/disconnect`, "POST", {});
    });
    button("Excluir", async () => {
      if (confirm(`Excluir ${c.name}? Só é possível se o número não tiver conversas.`)) await api(`/${c.id}`, "DELETE");
    });
    card.append(actions);

    const settings = el("details");
    settings.append(el("summary", "Nome e usuários com acesso"));
    const box = el("div");
    const name = el("input", undefined, "crm-input");
    name.value = c.name;
    name.maxLength = 80;
    name.setAttribute("aria-label", "Nome do número");
    name.onkeydown = (e) => { if (e.key === "Enter") e.preventDefault(); };
    const people = userChecks(c.user_ids);
    const save = el("button", "Salvar acesso", "crm-btn crm-btn--primary");
    save.type = "button";
    save.onclick = guard(async () => {
      await api(`/${c.id}`, "PATCH", { name: name.value, user_ids: checked(people) });
      settings.open = false;
      await refresh();
    });
    box.append(name, people, save);
    settings.append(box);
    card.append(settings);
    return card;
  }

  async function refresh() {
    const data = await api(".json");
    users = data.users;
    status.textContent = data.configured ? "" : "Servidor WhatsApp não configurado.";
    // Não recria a lista enquanto alguém edita o acesso.
    if (cardsRoot.querySelector("details[open]")) return;
    timers.forEach(clearTimeout);
    timers = [];
    cardsRoot.replaceChildren(...data.connections.map(renderCard));
    if (!data.connections.length)
      cardsRoot.append(el("small", "Nenhum número ainda. Adicione o primeiro abaixo."));
    const newUsers = document.getElementById("wan-new-users");
    if (!newUsers.dataset.ready) {
      newUsers.replaceChildren(userChecks());
      newUsers.dataset.ready = "1";
    }
  }

  const nameInput = document.getElementById("wan-name");
  nameInput.onkeydown = (e) => {
    if (e.key !== "Enter") return;
    e.preventDefault();
    document.getElementById("wan-add").click();
  };
  document.getElementById("wan-add").onclick = guard(async () => {
    const created = await api("", "POST", {
      name: nameInput.value,
      user_ids: checked(document.getElementById("wan-new-users")),
    });
    nameInput.value = "";
    document.querySelectorAll("#wan-new-users input").forEach((i) => (i.checked = false));
    say(`Número ${created.name} criado. Leia o QR que vai aparecer.`);
    await refresh();
  });

  if (provider)
    provider.addEventListener("change", () => {
      section.hidden = provider.value !== "evolution";
    });

  const tick = async () => {
    if (!section.hidden && !document.hidden) await guard(refresh)();
    setTimeout(tick, 4000);
  };
  guard(refresh)();
  setTimeout(tick, 4000);
})();
