// Editor de e-mail por blocos (/crm/email_templates/new e /edit).
//
// O estado (lista de blocos + estilo global) vive aqui e é serializado em dois
// campos ocultos (blocks_json / design_json). O HTML do e-mail é sempre
// renderizado pelo servidor (POST /email_templates/preview) — o mesmo que é
// enviado de verdade — e mostrado num iframe onde cada bloco é clicável.
(() => {
  const root = document.getElementById("email-builder");
  const form = document.getElementById("email-template-form");
  if (!root || !form) return;

  const $ = (selector, scope = document) => scope.querySelector(selector);
  const $$ = (selector, scope = document) => Array.from(scope.querySelectorAll(selector));
  const csrfToken = () => $('meta[name="csrf-token"]')?.content;
  const uid = () => `b${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;
  const clone = (value) => JSON.parse(JSON.stringify(value));
  const escapeHtml = (text) =>
    String(text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  // ---------------------------------------------------------------- schema --

  const ALIGN = { kind: "align", key: "align", label: "Alinhamento" };
  const PADDING_OPTIONS = [["none", "Sem"], ["sm", "P"], ["md", "M"], ["lg", "G"]];
  const COMMON_FIELDS = [
    { kind: "color", key: "bg", label: "Fundo do bloco", empty: "Transparente" },
    { kind: "segmented", key: "pad", label: "Espaçamento interno", options: PADDING_OPTIONS },
  ];
  const COMMON_DEFAULTS = { bg: "", pad: "md" };
  const SOCIAL_NETWORKS = [
    ["instagram", "Instagram"], ["facebook", "Facebook"], ["tiktok", "TikTok"], ["youtube", "YouTube"], ["whatsapp", "WhatsApp"],
    ["linkedin", "LinkedIn"], ["x", "X"], ["pinterest", "Pinterest"], ["site", "Site"],
  ];

  const TYPES = {
    logo: {
      label: "Logo", icon: "fa-crown",
      defaults: { align: "center", size: "md" },
      fields: [
        { kind: "hint", text: "Usa o logo cadastrado em Configurações da loja (ou o nome da loja, se não houver logo)." },
        ALIGN,
        { kind: "segmented", key: "size", label: "Tamanho", options: [["sm", "P"], ["md", "M"], ["lg", "G"]] },
      ],
    },
    heading: {
      label: "Título", icon: "fa-heading",
      defaults: { text: "Seu título aqui", size: "lg", align: "center", color: "" },
      summary: (b) => b.text,
      fields: [
        { kind: "text", key: "text", label: "Texto", vars: true },
        { kind: "segmented", key: "size", label: "Tamanho", options: [["sm", "P"], ["md", "M"], ["lg", "G"], ["xl", "XG"]] },
        ALIGN,
        { kind: "color", key: "color", label: "Cor do texto", empty: "Padrão" },
      ],
    },
    text: {
      label: "Texto", icon: "fa-align-left",
      defaults: { text: "Escreva sua mensagem aqui.", size: "md", align: "center", color: "" },
      summary: (b) => b.text,
      fields: [
        { kind: "richtext", key: "text", label: "Texto" },
        { kind: "segmented", key: "size", label: "Tamanho", options: [["sm", "P"], ["md", "M"], ["lg", "G"]] },
        ALIGN,
        { kind: "color", key: "color", label: "Cor do texto", empty: "Padrão" },
      ],
    },
    image: {
      label: "Imagem", icon: "fa-image",
      defaults: { image_id: "", link: "", alt: "", width: "100", align: "center", rounded: false, pad: "none" },
      summary: (b) => (b.image_id ? b.alt || "Imagem enviada" : "Sem imagem"),
      fields: [
        { kind: "image", key: "image_id", label: "Imagem" },
        { kind: "url", key: "link", label: "Link ao clicar (opcional)" },
        { kind: "text", key: "alt", label: "Descrição (acessibilidade)" },
        { kind: "segmented", key: "width", label: "Largura", options: [["100", "100%"], ["75", "75%"], ["50", "50%"]] },
        ALIGN,
        { kind: "toggle", key: "rounded", label: "Cantos arredondados" },
      ],
    },
    button: {
      label: "Botão", icon: "fa-hand-pointer",
      defaults: { text: "Ver produtos", link: "", align: "center", color: "", text_color: "", style: "filled", full: false },
      summary: (b) => b.text,
      fields: [
        { kind: "text", key: "text", label: "Texto do botão", vars: true },
        { kind: "url", key: "link", label: "Link", hint: "Vazio = site da loja (ou a página do produto, no aviso de estoque)." },
        { kind: "segmented", key: "style", label: "Estilo", options: [["filled", "Preenchido"], ["outline", "Contorno"]] },
        ALIGN,
        { kind: "toggle", key: "full", label: "Largura total" },
        { kind: "color", key: "color", label: "Cor do botão", empty: "Cor da marca" },
        { kind: "color", key: "text_color", label: "Cor do texto", empty: "Branco" },
      ],
    },
    coupon: {
      label: "Cupom", icon: "fa-ticket",
      defaults: { code: "VOLTA10", label: "Use o cupom", color: "" },
      summary: (b) => b.code,
      fields: [
        { kind: "text", key: "code", label: "Código do cupom" },
        { kind: "text", key: "label", label: "Chamada acima do cupom", vars: true },
        { kind: "color", key: "color", label: "Cor", empty: "Cor da marca" },
      ],
    },
    product: {
      label: "Produto", icon: "fa-bag-shopping",
      defaults: { button_text: "Comprar agora", color: "" },
      summary: () => "Foto, nome e variação do produto",
      fields: [
        { kind: "hint", text: "Só aparece no aviso de \"De volta ao estoque\": mostra a foto, o nome e a variação do produto que voltou, com botão para a página dele." },
        { kind: "text", key: "button_text", label: "Texto do botão", vars: true },
        { kind: "color", key: "color", label: "Cor do botão", empty: "Cor da marca" },
      ],
    },
    image_text: {
      label: "Imagem + texto", icon: "fa-table-columns",
      defaults: { image_id: "", side: "left", heading: "Título da seção", text: "Conte mais sobre o produto ou a novidade.", button_text: "Saiba mais", link: "", color: "" },
      summary: (b) => b.heading || b.text,
      fields: [
        { kind: "image", key: "image_id", label: "Imagem" },
        { kind: "segmented", key: "side", label: "Imagem do lado", options: [["left", "Esquerdo"], ["right", "Direito"]] },
        { kind: "text", key: "heading", label: "Título", vars: true },
        { kind: "richtext", key: "text", label: "Texto" },
        { kind: "text", key: "button_text", label: "Texto do botão (vazio = sem botão)", vars: true },
        { kind: "url", key: "link", label: "Link do botão" },
        { kind: "color", key: "color", label: "Cor do botão", empty: "Cor da marca" },
      ],
    },
    gallery: {
      label: "Vitrine", icon: "fa-grip",
      defaults: { items: [{ image_id: "", link: "", caption: "" }, { image_id: "", link: "", caption: "" }] },
      summary: (b) => `${b.items.length} ${b.items.length === 1 ? "imagem" : "imagens"} lado a lado`,
      fields: [{ kind: "items", key: "items", label: "Imagens (até 3, lado a lado)" }],
    },
    divider: {
      label: "Divisor", icon: "fa-minus",
      defaults: { color: "", thickness: "1" },
      fields: [
        { kind: "segmented", key: "thickness", label: "Espessura", options: [["1", "Fina"], ["2", "Média"], ["4", "Grossa"]] },
        { kind: "color", key: "color", label: "Cor", empty: "Cinza claro" },
      ],
    },
    spacer: {
      label: "Espaço", icon: "fa-arrows-up-down",
      defaults: { height: "24", pad: "none" },
      summary: (b) => `${b.height}px`,
      fields: [
        { kind: "segmented", key: "height", label: "Altura", options: [["8", "8"], ["16", "16"], ["24", "24"], ["32", "32"], ["48", "48"], ["64", "64"], ["96", "96"]] },
      ],
    },
    social: {
      label: "Redes sociais", icon: "fa-share-nodes",
      defaults: { ...Object.fromEntries(SOCIAL_NETWORKS.map(([key]) => [key, ""])), shape: "circle", tone: "custom", color: "", size: "md", align: "center" },
      summary: (b) => SOCIAL_NETWORKS.filter(([key]) => b[key]).map(([, label]) => label).join(", ") || "Sem links",
      fields: [
        { kind: "segmented", key: "shape", label: "Formato dos ícones", options: [["circle", "Círculo"], ["square", "Quadrado"]] },
        { kind: "segmented", key: "tone", label: "Cores", options: [["custom", "Cor única"], ["brand", "Cores da rede"]] },
        { kind: "color", key: "color", label: "Cor dos ícones (cor única)", empty: "Preto" },
        { kind: "segmented", key: "size", label: "Tamanho", options: [["sm", "P"], ["md", "M"], ["lg", "G"]] },
        ALIGN,
        ...SOCIAL_NETWORKS.map(([key, label]) => ({ kind: "url", key, label: key === "whatsapp" ? "WhatsApp (link wa.me)" : label })),
      ],
    },
    menu: {
      label: "Menu", icon: "fa-bars",
      defaults: {
        items: [{ label: "Novidades", link: "" }, { label: "Mulher", link: "" }, { label: "Sale", link: "" }],
        size: "md", align: "center", color: "", uppercase: true,
      },
      summary: (b) => b.items.map((item) => item.label).filter(Boolean).join(" · ") || "Sem links",
      fields: [
        { kind: "links", key: "items", label: "Links do menu (até 8)" },
        { kind: "segmented", key: "size", label: "Tamanho", options: [["sm", "P"], ["md", "M"], ["lg", "G"]] },
        ALIGN,
        { kind: "toggle", key: "uppercase", label: "Letras maiúsculas" },
        { kind: "color", key: "color", label: "Cor do texto", empty: "Padrão" },
      ],
    },
  };

  const SECTIONS = [
    { label: "Destaque", icon: "fa-star", blocks: [
      { type: "image" }, { type: "heading", size: "xl", text: "Novidade na loja" },
      { type: "text", text: "Uma frase curta e direta sobre o que você quer mostrar." }, { type: "button", text: "Quero ver" },
    ] },
    { label: "Oferta", icon: "fa-percent", blocks: [
      { type: "heading", text: "Oferta especial pra você" }, { type: "coupon" }, { type: "button", text: "Usar cupom", full: true },
    ] },
    { label: "Vitrine", icon: "fa-store", blocks: [
      { type: "heading", text: "Mais vendidos", size: "md" },
      { type: "gallery", items: [1, 2, 3].map(() => ({ image_id: "", link: "", caption: "Produto" })) },
    ] },
    { label: "Cabeçalho", icon: "fa-bars", blocks: [{ type: "logo" }, { type: "menu" }] },
    { label: "Assinatura", icon: "fa-signature", blocks: [
      { type: "divider" }, { type: "text", text: "Siga a gente nas redes 💜", size: "sm" }, { type: "social", pad: "sm" },
    ] },
  ];

  const DESIGN_FIELDS = [
    { kind: "text", key: "preheader", label: "Pré-cabeçalho", hint: "Texto curtinho que aparece ao lado do assunto na caixa de entrada.", vars: true },
    { kind: "color", key: "bg", label: "Fundo da página" },
    { kind: "color", key: "content_bg", label: "Fundo do e-mail" },
    { kind: "color", key: "text_color", label: "Cor do texto" },
    { kind: "select", key: "font", label: "Fonte", options: [
      ["arial", "Arial"], ["helvetica", "Helvetica"], ["verdana", "Verdana"], ["trebuchet", "Trebuchet"],
      ["georgia", "Georgia (serifa)"], ["times", "Times (serifa)"],
    ] },
    { kind: "segmented", key: "radius", label: "Cantos", options: [["0", "Retos"], ["4", "Suaves"], ["12", "Redondos"], ["24", "Pílula"]] },
  ];

  const VARIABLES = [
    { name: "nome", label: "Nome do cliente" },
    { name: "loja", label: "Nome da loja" },
    { name: "produto", label: "Produto (aviso de estoque)" },
    { name: "variacao", label: "Variação (aviso de estoque)" },
  ];

  // ----------------------------------------------------------------- state --

  const initial = JSON.parse($("#email-builder-state").textContent);
  const state = {
    blocks: initial.blocks.map((block) => normalize(block)),
    design: initial.design,
    selectedId: null,
  };

  const blocksInput = $("#email-field-blocks");
  const designInput = $("#email-field-design");
  const accentInput = $("#email-field-color");
  const preview = $("#email-preview");
  const frame = $("#email-preview-frame");
  const status = $("#eb-status");
  let dirty = false;

  function normalize(block) {
    const type = TYPES[block.type];
    const base = { ...COMMON_DEFAULTS, ...clone(type.defaults) };
    return { ...base, ...block, id: block.id || uid() };
  }

  function newBlock(type, overrides = {}) {
    return normalize({ type, ...clone(overrides), id: uid() });
  }

  const findIndex = (id) => state.blocks.findIndex((block) => block.id === id);
  const selected = () => state.blocks.find((block) => block.id === state.selectedId);

  // Campos de URL de miniatura não vão pro servidor.
  const serializableBlocks = () =>
    state.blocks.map(({ image_url, ...block }) => ({
      ...block,
      ...(block.items ? { items: block.items.map(({ image_url: _url, ...item }) => item) } : {}),
    }));

  function sync() {
    blocksInput.value = JSON.stringify(serializableBlocks());
    designInput.value = JSON.stringify(state.design);
  }

  // Toda alteração passa por aqui: salva nos campos ocultos, agenda o preview
  // e registra no histórico.
  function changed({ layers = true, inspector = false } = {}) {
    dirty = true;
    sync();
    if (layers) renderLayers();
    if (inspector) renderInspector();
    schedulePreview();
    recordHistory();
  }

  // --------------------------------------------------------------- history --

  const snapshot = () => JSON.stringify({ blocks: state.blocks, design: state.design, accent: accentInput.value });
  let history = [snapshot()];
  let pointer = 0;
  let historyTimer = null;
  const undoButton = $("#eb-undo");
  const redoButton = $("#eb-redo");

  function pushHistory() {
    historyTimer = null;
    const snap = snapshot();
    if (snap === history[pointer]) return;
    history = history.slice(0, pointer + 1);
    history.push(snap);
    if (history.length > 100) history.shift();
    pointer = history.length - 1;
    updateHistoryButtons();
  }

  function recordHistory() {
    clearTimeout(historyTimer);
    historyTimer = setTimeout(pushHistory, 450);
  }

  function flushHistory() {
    if (historyTimer) {
      clearTimeout(historyTimer);
      pushHistory();
    }
  }

  function restore(index) {
    pointer = index;
    const snap = JSON.parse(history[pointer]);
    state.blocks = snap.blocks;
    state.design = snap.design;
    accentInput.value = snap.accent;
    if (!selected()) state.selectedId = null;
    dirty = true;
    sync();
    renderAll();
    schedulePreview();
    updateHistoryButtons();
  }

  const undo = () => { flushHistory(); if (pointer > 0) restore(pointer - 1); };
  const redo = () => { flushHistory(); if (pointer < history.length - 1) restore(pointer + 1); };

  function updateHistoryButtons() {
    undoButton.disabled = pointer === 0;
    redoButton.disabled = pointer === history.length - 1;
  }

  // ------------------------------------------------------------ operations --

  function insertBlocks(blocks, index = null) {
    let at = index;
    if (at === null) {
      const current = findIndex(state.selectedId);
      at = current >= 0 ? current + 1 : state.blocks.length;
    }
    state.blocks.splice(at, 0, ...blocks);
    scrollAfterPreview = true;
    select(blocks[0].id, { silent: true });
    changed({ inspector: true });
  }

  function moveBlock(id, delta) {
    const index = findIndex(id);
    const target = index + delta;
    if (index < 0 || target < 0 || target >= state.blocks.length) return;
    const [block] = state.blocks.splice(index, 1);
    state.blocks.splice(target, 0, block);
    changed();
    flashStatus(delta < 0 ? "Bloco movido pra cima" : "Bloco movido pra baixo");
  }

  function moveBlockTo(id, index) {
    const from = findIndex(id);
    if (from < 0) return;
    const [block] = state.blocks.splice(from, 1);
    state.blocks.splice(index > from ? index - 1 : index, 0, block);
    changed();
  }

  function duplicateBlock(id) {
    const index = findIndex(id);
    if (index < 0) return;
    const copy = { ...clone(state.blocks[index]), id: uid() };
    insertBlocks([copy], index + 1);
    flashStatus("Bloco duplicado");
  }

  function removeBlock(id) {
    const index = findIndex(id);
    if (index < 0) return;
    state.blocks.splice(index, 1);
    state.selectedId = null;
    showPane(listTab);
    changed({ inspector: true });
    flashStatus("Bloco excluído — Ctrl+Z desfaz");
  }

  function updateField(block, key, value, options = {}) {
    block[key] = value;
    changed(options);
  }

  // ------------------------------------------------------------ selection --

  function select(id, { scroll = false, silent = false } = {}) {
    state.selectedId = id;
    if (!silent) {
      renderLayers();
      renderInspector();
    }
    showPane(id ? "inspector" : listTab);
    highlightPreview(scroll);
  }

  let listTab = "blocks";

  function showPane(name) {
    if (name === "blocks" || name === "structure") listTab = name;
    $$(".eb-pane", root).forEach((pane) => pane.classList.toggle("active", pane.dataset.pane === name));
    const tab = name === "inspector" ? listTab : name;
    $$(".eb-tabs__tab", root).forEach((button) => button.classList.toggle("active", button.dataset.tab === tab));
  }

  // --------------------------------------------------------------- palette --

  function renderPalette() {
    $("#eb-palette").innerHTML = Object.entries(TYPES)
      .map(([type, def]) => {
        return `<button type="button" class="eb-tile" draggable="true" data-add="${type}">
          <i class="fa-solid ${def.icon}"></i><span>${def.label}</span></button>`;
      })
      .join("");

    $("#eb-sections").innerHTML = SECTIONS.map(
      (section, index) => `<button type="button" class="eb-section-chip" draggable="true" data-section="${index}">
        <i class="fa-solid ${section.icon}"></i> ${section.label}</button>`,
    ).join("");
  }

  const blocksFromSource = (source) => {
    if (source.add) return [newBlock(source.add)];
    return SECTIONS[source.section].blocks.map(({ type, ...overrides }) => newBlock(type, overrides));
  };

  root.addEventListener("click", (event) => {
    const tile = event.target.closest("[data-add], [data-section]");
    if (!tile || tile.disabled) return;
    insertBlocks(blocksFromSource(tile.dataset));
    flashStatus("Bloco adicionado");
  });

  // ---------------------------------------------------------------- layers --

  const layersList = $("#eb-layers");

  function renderLayers() {
    $("#eb-count").textContent = `${state.blocks.length} ${state.blocks.length === 1 ? "bloco" : "blocos"}`;
    if (!state.blocks.length) {
      layersList.innerHTML = '<li class="eb-layers__empty"><i class="fa-solid fa-square-plus"></i> Arraste um bloco pra cá</li>';
      return;
    }
    layersList.innerHTML = state.blocks
      .map((block, index) => {
        const def = TYPES[block.type];
        const summary = def.summary ? def.summary(block) : "";
        return `<li class="eb-layer ${block.id === state.selectedId ? "active" : ""}" draggable="true" data-id="${block.id}">
          <span class="eb-layer__handle" title="Arraste pra reordenar"><i class="fa-solid fa-grip-vertical"></i></span>
          <span class="eb-layer__icon"><i class="fa-solid ${def.icon}"></i></span>
          <span class="eb-layer__text"><strong>${def.label}</strong>${summary ? `<small>${escapeHtml(String(summary).slice(0, 60))}</small>` : ""}</span>
          <span class="eb-layer__actions">
            <button type="button" data-layer-action="up" title="Subir" ${index === 0 ? "disabled" : ""}><i class="fa-solid fa-chevron-up"></i></button>
            <button type="button" data-layer-action="down" title="Descer" ${index === state.blocks.length - 1 ? "disabled" : ""}><i class="fa-solid fa-chevron-down"></i></button>
            <button type="button" data-layer-action="duplicate" title="Duplicar"><i class="fa-solid fa-copy"></i></button>
            <button type="button" data-layer-action="remove" title="Excluir"><i class="fa-solid fa-trash-can"></i></button>
          </span>
        </li>`;
      })
      .join("");
  }

  layersList.addEventListener("click", (event) => {
    const item = event.target.closest(".eb-layer");
    if (!item) return;
    const action = event.target.closest("[data-layer-action]")?.dataset.layerAction;
    if (action) {
      event.stopPropagation();
      runAction(action, item.dataset.id);
    } else {
      select(item.dataset.id, { scroll: true });
    }
  });

  function runAction(action, id) {
    if (action === "up") moveBlock(id, -1);
    if (action === "down") moveBlock(id, 1);
    if (action === "duplicate") duplicateBlock(id);
    if (action === "remove") removeBlock(id);
  }

  $$(".eb-inspector__actions [data-action]", root).forEach((button) => {
    button.addEventListener("click", () => state.selectedId && runAction(button.dataset.action, state.selectedId));
  });
  $("#eb-inspector-back").addEventListener("click", () => select(null));

  // ---------------------------------------------------------- drag & drop --
  // Arrastar da paleta (novo bloco/seção) ou de uma camada (reordenar) pra
  // dentro da lista de estrutura. Um marcador mostra onde o bloco vai cair.

  let dragSource = null;
  const marker = document.createElement("li");
  marker.className = "eb-drop-marker";

  root.addEventListener("dragstart", (event) => {
    const layer = event.target.closest?.(".eb-layer");
    const tile = event.target.closest?.("[data-add], [data-section]");
    if (layer) dragSource = { move: layer.dataset.id };
    else if (tile) dragSource = { ...tile.dataset };
    else return;
    event.dataTransfer.effectAllowed = layer ? "move" : "copy";
    event.dataTransfer.setData("text/plain", "email-block");
    root.classList.add("is-dragging");
    layer?.classList.add("is-dragged");
  });

  root.addEventListener("dragend", () => {
    dragSource = null;
    marker.remove();
    clearFrameMarker();
    root.classList.remove("is-dragging");
    $$(".is-dragged", root).forEach((element) => element.classList.remove("is-dragged"));
  });

  function dropIndex(clientY) {
    const items = $$(".eb-layer", layersList);
    const index = items.findIndex((item) => {
      const rect = item.getBoundingClientRect();
      return clientY < rect.top + rect.height / 2;
    });
    return index === -1 ? items.length : index;
  }

  layersList.addEventListener("dragover", (event) => {
    if (!dragSource) return;
    event.preventDefault();
    const index = dropIndex(event.clientY);
    const items = $$(".eb-layer", layersList);
    if (items[index]) layersList.insertBefore(marker, items[index]);
    else layersList.appendChild(marker);
  });

  layersList.addEventListener("dragleave", (event) => {
    if (!layersList.contains(event.relatedTarget)) marker.remove();
  });

  layersList.addEventListener("drop", (event) => {
    if (!dragSource) return;
    event.preventDefault();
    marker.remove();
    const index = dropIndex(event.clientY);
    if (dragSource.move) moveBlockTo(dragSource.move, index);
    else insertBlocks(blocksFromSource(dragSource), index);
  });

  // ------------------------------------------------------------- inspector --

  const inspectorBody = $("#eb-inspector-body");

  function renderInspector() {
    const block = selected();
    if (!block) {
      inspectorBody.innerHTML = "";
      return;
    }
    const def = TYPES[block.type];
    $("#eb-inspector-title").innerHTML = `<i class="fa-solid ${def.icon}"></i> ${def.label}`;
    inspectorBody.innerHTML = "";
    def.fields.forEach((field) => inspectorBody.appendChild(buildField(field, block)));

    const appearance = document.createElement("details");
    appearance.className = "eb-appearance";
    appearance.open = Boolean(block.bg) || block.pad !== (def.defaults.pad || COMMON_DEFAULTS.pad);
    appearance.innerHTML = '<summary><i class="fa-solid fa-fill-drip"></i> Fundo e espaçamento</summary>';
    COMMON_FIELDS.forEach((field) => appearance.appendChild(buildField(field, block)));
    inspectorBody.appendChild(appearance);
  }

  function fieldWrapper(field) {
    const wrapper = document.createElement("div");
    wrapper.className = "eb-field";
    if (field.label) {
      const label = document.createElement("label");
      label.className = "crm-label";
      label.textContent = field.label;
      wrapper.appendChild(label);
    }
    return wrapper;
  }

  function appendHint(wrapper, text) {
    if (!text) return;
    const hint = document.createElement("span");
    hint.className = "cpform-field__hint";
    hint.textContent = text;
    wrapper.appendChild(hint);
  }

  // target = objeto que guarda o valor (bloco, item da vitrine ou design)
  function buildField(field, target, onChange = (key, value, opts) => updateField(target, key, value, opts)) {
    const wrapper = fieldWrapper(field);
    const value = target[field.key];

    switch (field.kind) {
      case "hint": {
        appendHint(wrapper, field.text);
        wrapper.classList.add("eb-field--hint");
        return wrapper;
      }
      case "text":
      case "url": {
        const input = document.createElement("input");
        input.type = field.kind === "url" ? "url" : "text";
        input.className = "crm-input";
        input.value = value ?? "";
        if (field.kind === "url") input.placeholder = "https://...";
        input.addEventListener("input", () => onChange(field.key, input.value));
        if (field.kind === "url") {
          input.addEventListener("blur", () => {
            const url = input.value.trim();
            if (url && !/^https?:\/\//i.test(url)) {
              input.value = `https://${url}`;
              onChange(field.key, input.value);
            }
          });
        }
        wrapper.appendChild(input);
        if (field.vars) wrapper.appendChild(variableChips(input));
        break;
      }
      case "richtext": {
        const textarea = document.createElement("textarea");
        textarea.className = "crm-input eb-richtext";
        textarea.rows = 5;
        textarea.value = value ?? "";
        textarea.addEventListener("input", () => onChange(field.key, textarea.value));
        wrapper.appendChild(formatToolbar(textarea));
        wrapper.appendChild(textarea);
        wrapper.appendChild(variableChips(textarea));
        break;
      }
      case "select": {
        const select = document.createElement("select");
        select.className = "crm-input";
        select.innerHTML = field.options
          .map(([optionValue, label]) => `<option value="${optionValue}" ${optionValue === value ? "selected" : ""}>${label}</option>`)
          .join("");
        select.addEventListener("change", () => onChange(field.key, select.value, { layers: false }));
        wrapper.appendChild(select);
        break;
      }
      case "align":
      case "segmented": {
        const options = field.kind === "align"
          ? [["left", '<i class="fa-solid fa-align-left"></i>'], ["center", '<i class="fa-solid fa-align-center"></i>'], ["right", '<i class="fa-solid fa-align-right"></i>']]
          : field.options;
        const group = document.createElement("div");
        group.className = "eb-segmented";
        group.innerHTML = options
          .map(([optionValue, label]) => `<button type="button" data-value="${optionValue}" class="${optionValue === value ? "active" : ""}">${label}</button>`)
          .join("");
        group.addEventListener("click", (event) => {
          const button = event.target.closest("button");
          if (!button) return;
          $$("button", group).forEach((b) => b.classList.toggle("active", b === button));
          onChange(field.key, button.dataset.value);
        });
        wrapper.appendChild(group);
        break;
      }
      case "toggle": {
        wrapper.classList.add("eb-field--inline");
        const label = $("label", wrapper);
        const input = document.createElement("input");
        input.type = "checkbox";
        input.className = "cform-toggle__input";
        input.checked = Boolean(value);
        input.addEventListener("change", () => onChange(field.key, input.checked, { layers: false }));
        wrapper.insertBefore(input, label);
        label.classList.remove("crm-label");
        label.addEventListener("click", () => input.click());
        break;
      }
      case "color": {
        wrapper.appendChild(colorControl(value, field.empty, (color) => onChange(field.key, color, { layers: false })));
        break;
      }
      case "image": {
        wrapper.appendChild(imageControl(target, field.key, onChange));
        break;
      }
      case "links": {
        wrapper.appendChild(linksControl(target));
        break;
      }
      case "items": {
        wrapper.appendChild(itemsControl(target));
        break;
      }
      default:
        break;
    }
    appendHint(wrapper, field.hint);
    return wrapper;
  }

  const SWATCHES = ["#111111", "#ffffff", "#f4f4f5", "#7c3aed", "#e11d48", "#f59e0b", "#16a34a", "#0ea5e9"];

  function colorControl(value, emptyLabel, onPick) {
    const control = document.createElement("div");
    control.className = "eb-color";
    const swatchesHtml = SWATCHES.map((c) => `<button type="button" class="eb-color__preset" data-color="${c}" style="background:${c}" title="${c}"></button>`).join("");
    control.innerHTML = `
      <input type="color" class="eb-color__swatch" value="${value || "#ffffff"}">
      <span class="eb-color__value">${value || emptyLabel || ""}</span>
      <span class="eb-color__presets">${swatchesHtml}</span>
      ${emptyLabel ? `<button type="button" class="eb-link-btn eb-color__reset" title="Voltar ao padrão" ${value ? "" : "hidden"}><i class="fa-solid fa-rotate-left"></i> ${emptyLabel}</button>` : ""}`;
    const picker = $("input", control);
    const label = $(".eb-color__value", control);
    const reset = $(".eb-color__reset", control);
    if (!value && emptyLabel) control.classList.add("is-empty");

    const apply = (color) => {
      label.textContent = color || emptyLabel;
      control.classList.toggle("is-empty", !color);
      if (reset) reset.hidden = !color;
      if (color) picker.value = color;
      onPick(color);
    };
    picker.addEventListener("input", () => apply(picker.value));
    control.addEventListener("click", (event) => {
      const preset = event.target.closest("[data-color]");
      if (preset) apply(preset.dataset.color);
    });
    reset?.addEventListener("click", () => apply(""));
    return control;
  }

  function variableChips(input) {
    const chips = document.createElement("div");
    chips.className = "eb-vars";
    chips.innerHTML = VARIABLES
      .map((variable) => `<button type="button" data-var="${variable.name}" title="Inserir ${variable.label}">{${variable.name}}</button>`)
      .join("");
    chips.addEventListener("click", (event) => {
      const chip = event.target.closest("[data-var]");
      if (chip) insertAtCursor(input, `{${chip.dataset.var}}`);
    });
    return chips;
  }

  function insertAtCursor(input, text, selectFrom = null, selectTo = null) {
    const start = input.selectionStart ?? input.value.length;
    const end = input.selectionEnd ?? input.value.length;
    input.value = input.value.slice(0, start) + text + input.value.slice(end);
    input.focus();
    const from = selectFrom === null ? start + text.length : start + selectFrom;
    const to = selectTo === null ? from : start + selectTo;
    input.setSelectionRange(from, to);
    input.dispatchEvent(new Event("input", { bubbles: true }));
  }

  function wrapSelection(textarea, marker) {
    const { selectionStart: start, selectionEnd: end, value } = textarea;
    const chosen = value.slice(start, end) || "texto";
    insertAtCursor(textarea, `${marker}${chosen}${marker}`, marker.length, marker.length + chosen.length);
  }

  function formatToolbar(textarea) {
    const toolbar = document.createElement("div");
    toolbar.className = "eb-format";
    toolbar.innerHTML = `
      <button type="button" data-format="bold" title="Negrito"><i class="fa-solid fa-bold"></i></button>
      <button type="button" data-format="italic" title="Itálico"><i class="fa-solid fa-italic"></i></button>
      <button type="button" data-format="link" title="Link"><i class="fa-solid fa-link"></i></button>
      <span class="eb-muted">**negrito** · *itálico* · [texto](https://link)</span>`;
    toolbar.addEventListener("click", (event) => {
      const format = event.target.closest("[data-format]")?.dataset.format;
      if (format === "bold") wrapSelection(textarea, "**");
      if (format === "italic") wrapSelection(textarea, "*");
      if (format === "link") {
        const { selectionStart: start, selectionEnd: end, value } = textarea;
        const label = value.slice(start, end) || "clique aqui";
        const snippet = `[${label}](https://)`;
        insertAtCursor(textarea, snippet, label.length + 3, snippet.length - 1);
      }
    });
    return toolbar;
  }

  // Upload: arraste um arquivo ou clique. A imagem vai direto pro servidor e o
  // bloco guarda só o signed_id.
  function imageControl(target, key, onChange) {
    const control = document.createElement("div");
    control.className = "eb-image";
    const render = () => {
      const url = target.image_url;
      control.innerHTML = `
        <label class="eb-image__drop ${url ? "has-image" : ""}">
          ${url ? `<img src="${escapeHtml(url)}" alt="">` : '<i class="fa-solid fa-cloud-arrow-up"></i><span>Arraste uma imagem ou <u>clique para enviar</u></span><small>PNG, JPG, GIF ou WEBP · até 5 MB</small>'}
          <input type="file" accept="image/png,image/jpeg,image/gif,image/webp" hidden>
        </label>
        ${url ? '<div class="eb-image__actions"><button type="button" class="eb-link-btn" data-image="replace"><i class="fa-solid fa-arrows-rotate"></i> Trocar</button><button type="button" class="eb-link-btn eb-link-btn--danger" data-image="remove"><i class="fa-solid fa-trash-can"></i> Remover</button></div>' : ""}`;
    };
    render();

    const upload = async (file) => {
      if (!file) return;
      control.classList.add("is-uploading");
      flashStatus("Enviando imagem…", true);
      const data = new FormData();
      data.append("file", file);
      try {
        const response = await fetch(preview.dataset.uploadUrl, {
          method: "POST", body: data, headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
        });
        const json = await response.json();
        if (!response.ok) throw new Error(json.error || "Falha no envio");
        target.image_url = json.url;
        onChange(key, json.signed_id);
        render();
        flashStatus("Imagem enviada");
      } catch (error) {
        flashStatus(error.message || "Não foi possível enviar a imagem", false, true);
      } finally {
        control.classList.remove("is-uploading");
      }
    };

    control.addEventListener("change", (event) => upload(event.target.files?.[0]));
    control.addEventListener("click", (event) => {
      const action = event.target.closest("[data-image]")?.dataset.image;
      if (action === "replace") $("input[type=file]", control).click();
      if (action === "remove") {
        target.image_url = "";
        onChange(key, "");
        render();
      }
    });
    control.addEventListener("dragover", (event) => {
      if (!event.dataTransfer.types.includes("Files")) return;
      event.preventDefault();
      control.classList.add("is-over");
    });
    control.addEventListener("dragleave", () => control.classList.remove("is-over"));
    control.addEventListener("drop", (event) => {
      if (!event.dataTransfer.files.length) return;
      event.preventDefault();
      control.classList.remove("is-over");
      upload(event.dataTransfer.files[0]);
    });
    return control;
  }

  function itemsControl(block) {
    const list = document.createElement("div");
    list.className = "eb-items";
    const render = () => {
      list.innerHTML = "";
      block.items.forEach((item, index) => {
        const card = document.createElement("div");
        card.className = "eb-items__card";
        card.innerHTML = `<div class="eb-items__head"><strong>Imagem ${index + 1}</strong>
          ${block.items.length > 1 ? '<button type="button" class="eb-link-btn eb-link-btn--danger" data-remove-item><i class="fa-solid fa-trash-can"></i></button>' : ""}</div>`;
        const onItemChange = (key, value) => { item[key] = value; changed(); };
        card.appendChild(buildField({ kind: "image", key: "image_id" }, item, onItemChange));
        card.appendChild(buildField({ kind: "text", key: "caption", label: "Legenda" }, item, onItemChange));
        card.appendChild(buildField({ kind: "url", key: "link", label: "Link" }, item, onItemChange));
        $("[data-remove-item]", card)?.addEventListener("click", () => {
          block.items.splice(index, 1);
          changed();
          render();
        });
        list.appendChild(card);
      });
      if (block.items.length < 3) {
        const add = document.createElement("button");
        add.type = "button";
        add.className = "crm-btn eb-items__add";
        add.innerHTML = '<i class="fa-solid fa-plus"></i> Adicionar imagem';
        add.addEventListener("click", () => {
          block.items.push({ image_id: "", link: "", caption: "" });
          changed();
          render();
        });
        list.appendChild(add);
      }
    };
    render();
    return list;
  }

  function linksControl(block) {
    const MAX_LINKS = 8;
    const list = document.createElement("div");
    list.className = "eb-items";
    const render = () => {
      list.innerHTML = "";
      block.items.forEach((item, index) => {
        const card = document.createElement("div");
        card.className = "eb-items__card";
        card.innerHTML = `<div class="eb-items__head"><strong>Link ${index + 1}</strong>
          ${block.items.length > 1 ? '<button type="button" class="eb-link-btn eb-link-btn--danger" data-remove-item><i class="fa-solid fa-trash-can"></i></button>' : ""}</div>`;
        const onItemChange = (key, value) => { item[key] = value; changed(); };
        card.appendChild(buildField({ kind: "text", key: "label", label: "Texto" }, item, onItemChange));
        card.appendChild(buildField({ kind: "url", key: "link", label: "Link" }, item, onItemChange));
        $("[data-remove-item]", card)?.addEventListener("click", () => {
          block.items.splice(index, 1);
          changed();
          render();
        });
        list.appendChild(card);
      });
      if (block.items.length < MAX_LINKS) {
        const add = document.createElement("button");
        add.type = "button";
        add.className = "crm-btn eb-items__add";
        add.innerHTML = '<i class="fa-solid fa-plus"></i> Adicionar link';
        add.addEventListener("click", () => {
          block.items.push({ label: "", link: "" });
          changed();
          render();
        });
        list.appendChild(add);
      }
    };
    render();
    return list;
  }

  // ---------------------------------------------------------------- design --

  function renderDesign() {
    const container = $("#eb-design");
    container.innerHTML = "";
    DESIGN_FIELDS.forEach((field) => {
      container.appendChild(buildField(field, state.design, (key, value) => {
        state.design[key] = value;
        changed({ layers: false });
      }));
    });
  }

  const accentLabel = $('[data-color-value-for="email-field-color"]');
  const syncAccentLabel = () => { accentLabel.textContent = accentInput.value; };
  accentInput.addEventListener("input", () => { syncAccentLabel(); changed({ layers: false }); });

  // --------------------------------------------------------------- preview --

  const PREVIEW_DELAY_MS = 250;
  let scrollAfterPreview = false;
  let previewTimer;
  let previewController;

  function formPayload() {
    sync();
    const data = new FormData(form);
    data.delete("_method");
    data.delete("authenticity_token");
    return data;
  }

  async function refreshPreview() {
    previewController?.abort();
    previewController = new AbortController();

    const response = await fetch(preview.dataset.url, {
      method: "POST",
      body: formPayload(),
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
      signal: previewController.signal,
    }).catch(() => null);
    if (!response?.ok) return;

    const email = await response.json();
    $("#email-preview-subject").textContent = email.subject || "(sem assunto)";
    $("#email-preview-preheader").textContent = email.preheader || "";
    frame.srcdoc = email.html;
  }

  function schedulePreview() {
    clearTimeout(previewTimer);
    previewTimer = setTimeout(refreshPreview, PREVIEW_DELAY_MS);
  }

  function fitFrame() {
    const doc = frame.contentDocument;
    if (!doc?.documentElement) return;
    frame.style.height = "0px";
    frame.style.height = `${doc.documentElement.scrollHeight}px`;
  }

  const BAR_ICONS = {
    up: '<path d="m6 15 6-6 6 6"/>',
    down: '<path d="m6 9 6 6 6-6"/>',
    duplicate: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/>',
    remove: '<path d="M4 7h16M10 11v6M14 11v6M6 7l1 12h10l1-12M9 7V4h6v3"/>',
  };
  const BAR_TITLES = { up: "Subir", down: "Descer", duplicate: "Duplicar", remove: "Excluir" };

  function canvasBar(doc, id) {
    const index = findIndex(id);
    const bar = doc.createElement("div");
    bar.className = "eb-canvas-bar";
    bar.style.cssText = "position:absolute;top:6px;right:6px;z-index:10;display:flex;gap:2px;padding:3px;border-radius:8px;background:#7c3aed;box-shadow:0 4px 12px rgba(0,0,0,.25);";

    Object.entries(BAR_ICONS).forEach(([action, path]) => {
      const button = doc.createElement("button");
      button.type = "button";
      button.title = BAR_TITLES[action];
      button.disabled = (action === "up" && index === 0) || (action === "down" && index === state.blocks.length - 1);
      button.style.cssText = `width:26px;height:26px;padding:0;border:0;border-radius:6px;background:transparent;cursor:pointer;display:flex;align-items:center;justify-content:center;opacity:${button.disabled ? 0.4 : 1};`;
      button.innerHTML = `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">${path}</svg>`;
      button.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        if (!button.disabled) runAction(action, id);
      });
      bar.appendChild(button);
    });
    return bar;
  }

  function highlightPreview(scroll) {
    const doc = frame.contentDocument;
    if (!doc) return;
    $$("[data-block-id]", doc).forEach((cell) => cell.classList.toggle("is-selected", cell.dataset.blockId === state.selectedId));
    $$(".eb-canvas-bar", doc).forEach((bar) => bar.remove());
    const cell = state.selectedId && $(`[data-block-id="${CSS.escape(state.selectedId)}"]`, doc);
    if (cell) {
      cell.style.position = "relative";
      cell.appendChild(canvasBar(doc, state.selectedId));
    }
    if (!scroll || !state.selectedId) return;
    const phone = $("#eb-device-frame");
    const mobile = phone.classList.contains("is-mobile");
    if (cell) {
      const offset = cell.getBoundingClientRect().top + frame.offsetTop;
      const top = mobile ? offset - 20 : offset * zoomLevel() - 40;
      (mobile ? phone : $("#eb-viewport")).scrollTo({ top: Math.max(top, 0), behavior: "smooth" });
    }
  }

  let frameMarker = null;

  function clearFrameMarker() {
    frameMarker?.remove();
    frameMarker = null;
  }

  function frameDrop(doc, clientY) {
    const cells = $$("[data-block-id]", doc);
    const found = cells.findIndex((cell) => {
      const rect = cell.getBoundingClientRect();
      return clientY < rect.top + rect.height / 2;
    });
    return { cells, index: found === -1 ? cells.length : found };
  }

  function bindFrameDrop(doc) {
    doc.addEventListener("dragover", (event) => {
      if (!dragSource) return;
      event.preventDefault();
      const { cells, index } = frameDrop(doc, event.clientY);
      const edge = cells[index] ? cells[index].getBoundingClientRect().top : (cells.at(-1)?.getBoundingClientRect().bottom ?? 0);
      if (!frameMarker) {
        frameMarker = doc.createElement("div");
        frameMarker.style.cssText = "position:absolute;left:0;right:0;height:3px;background:#7c3aed;box-shadow:0 0 0 3px rgba(124,58,237,.2);pointer-events:none;z-index:20;";
        doc.body.appendChild(frameMarker);
      }
      frameMarker.style.top = `${edge + doc.documentElement.scrollTop - 1.5}px`;
    });
    doc.addEventListener("dragleave", (event) => {
      if (!event.relatedTarget) clearFrameMarker();
    });
    doc.addEventListener("drop", (event) => {
      if (!dragSource) return;
      event.preventDefault();
      clearFrameMarker();
      const { index } = frameDrop(doc, event.clientY);
      if (dragSource.move) moveBlockTo(dragSource.move, index);
      else insertBlocks(blocksFromSource(dragSource), index);
    });
  }

  frame.addEventListener("load", () => {
    const doc = frame.contentDocument;
    frameMarker = null;
    bindFrameDrop(doc);
    doc.addEventListener("keydown", confirmReload);
    fitFrame();
    // Imagens carregam depois do load do srcdoc em alguns navegadores.
    $$("img", doc).forEach((img) => img.addEventListener("load", fitFrame));
    doc.addEventListener("click", (event) => {
      event.preventDefault();
      const cell = event.target.closest("[data-block-id]");
      if (cell) select(cell.dataset.blockId);
    });
    highlightPreview(scrollAfterPreview);
    scrollAfterPreview = false;
  });

  const ZOOM_STEPS = [50, 65, 80, 100];
  let zoomIndex = 0;
  const zoomLevel = () => ZOOM_STEPS[zoomIndex] / 100;

  $$("[data-zoom]", root).forEach((button) => {
    button.addEventListener("click", () => {
      zoomIndex = Math.min(Math.max(zoomIndex + Number(button.dataset.zoom), 0), ZOOM_STEPS.length - 1);
      $("#eb-device-frame").style.zoom = zoomLevel();
      $("#eb-zoom-value").textContent = `${ZOOM_STEPS[zoomIndex]}%`;
    });
  });
  $("#eb-device-frame").style.zoom = zoomLevel();

  $$("[data-device]", root).forEach((button) => {
    button.addEventListener("click", () => {
      $$("[data-device]", root).forEach((b) => b.classList.toggle("active", b === button));
      $("#eb-device-frame").classList.toggle("is-mobile", button.dataset.device === "mobile");
      setTimeout(fitFrame, 260);
    });
  });

  const testEmail = $("#eb-test-email");
  const testButton = $("#eb-test-send");

  async function sendTest() {
    if (!testEmail.value.trim() || !testEmail.checkValidity()) return flashStatus("Informe um e-mail válido.", false, true);

    const data = formPayload();
    data.append("test_email", testEmail.value.trim());
    testButton.disabled = true;
    flashStatus("Enviando teste…", true);

    const response = await fetch(testButton.dataset.url, {
      method: "POST",
      body: data,
      headers: { Accept: "application/json", "X-CSRF-Token": csrfToken() },
    }).catch(() => null);
    const result = await response?.json().catch(() => ({}));
    testButton.disabled = false;

    if (response?.ok) return flashStatus(result.message);
    flashStatus(result?.error || "Não foi possível enviar o teste.", false, true);
  }

  testButton.addEventListener("click", sendTest);
  testEmail.addEventListener("keydown", (event) => {
    if (event.key !== "Enter") return;
    event.preventDefault();
    sendTest();
  });

  let statusTimer;
  function flashStatus(text, sticky = false, error = false) {
    status.textContent = text;
    status.classList.toggle("is-error", error);
    status.classList.add("visible");
    clearTimeout(statusTimer);
    if (!sticky) statusTimer = setTimeout(() => status.classList.remove("visible"), 2200);
  }

  // ------------------------------------------------------------------ tabs --

  $$(".eb-tabs__tab", root).forEach((tab) => {
    tab.addEventListener("click", () => {
      if (["blocks", "structure"].includes(tab.dataset.tab) && state.selectedId) state.selectedId = null;
      renderLayers();
      highlightPreview(false);
      showPane(tab.dataset.tab);
    });
  });

  // Campos fora do editor (nome, assunto...) também atualizam o preview.
  form.addEventListener("input", (event) => {
    if (!root.contains(event.target)) {
      dirty = true;
      schedulePreview();
    }
  });
  form.addEventListener("change", (event) => {
    if (!root.contains(event.target)) schedulePreview();
  });

  // -------------------------------------------------------------- keyboard --

  const typing = (element) => element?.matches?.("input, textarea, select, [contenteditable]");

  document.addEventListener("keydown", (event) => {
    const mod = event.metaKey || event.ctrlKey;
    if (mod && event.key.toLowerCase() === "z" && !typing(document.activeElement)) {
      event.preventDefault();
      if (event.shiftKey) redo();
      else undo();
      return;
    }
    if (mod && event.key.toLowerCase() === "y" && !typing(document.activeElement)) {
      event.preventDefault();
      redo();
      return;
    }
    if (!state.selectedId || typing(document.activeElement)) return;
    if (event.key === "Delete" || event.key === "Backspace") {
      event.preventDefault();
      removeBlock(state.selectedId);
    } else if (mod && event.key.toLowerCase() === "d") {
      event.preventDefault();
      duplicateBlock(state.selectedId);
    } else if (event.altKey && event.key === "ArrowUp") {
      event.preventDefault();
      moveBlock(state.selectedId, -1);
    } else if (event.altKey && event.key === "ArrowDown") {
      event.preventDefault();
      moveBlock(state.selectedId, 1);
    } else if (event.key === "Escape") {
      select(null);
    }
  });

  undoButton.addEventListener("click", undo);
  redoButton.addEventListener("click", redo);

  // Aviso ao sair com alterações não salvas.
  form.addEventListener("submit", () => {
    sync();
    dirty = false;
  });
  window.addEventListener("beforeunload", (event) => {
    if (!dirty) return;
    event.preventDefault();
    event.returnValue = "";
  });

  const confirmLeave = (title, confirmLabel) =>
    window.CrmConfirm.ask({
      title,
      message: "Você tem alterações que ainda não foram salvas. Se continuar, elas serão perdidas.",
      confirmLabel,
      cancelLabel: "Continuar editando",
    });

  document.addEventListener("click", async (event) => {
    const link = event.target.closest?.("a[href]");
    const modified = event.metaKey || event.ctrlKey || event.shiftKey || event.altKey;
    if (!dirty || !link || !window.CrmConfirm || link.target === "_blank" || event.defaultPrevented || modified) return;

    const url = new URL(link.href, location.href);
    if (url.origin !== location.origin || (url.pathname === location.pathname && url.hash)) return;

    event.preventDefault();
    if (!(await confirmLeave("Sair sem salvar?", "Sair sem salvar"))) return;

    dirty = false;
    location.href = link.href;
  });

  async function confirmReload(event) {
    const reload = event.key === "F5" || ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "r");
    if (!reload || !dirty || !window.CrmConfirm) return;

    event.preventDefault();
    if (!(await confirmLeave("Atualizar a página?", "Atualizar sem salvar"))) return;

    dirty = false;
    location.reload();
  }

  document.addEventListener("keydown", confirmReload);

  // ------------------------------------------------------------------ boot --

  function renderAll() {
    renderPalette();
    renderLayers();
    renderInspector();
    renderDesign();
    syncAccentLabel();
    showPane(state.selectedId ? "inspector" : listTab);
  }

  sync();
  history = [snapshot()];
  renderAll();
  refreshPreview();
})();
