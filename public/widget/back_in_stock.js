(() => {
  const script = document.currentScript;
  const token = script?.dataset.token;
  const productEnabled = script?.dataset.aviseMe === "true";
  const handle = location.pathname.match(/\/products\/([^/?#]+)/)?.[1];
  if (!token || !handle) return;

  const API = new URL(script.src).origin;
  const SYNC_INTERVAL_MS = 500;

  const ICONS = {
    bell: '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/></svg>',
    spinner: '<svg class="mewtda-bis-spinner" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" aria-hidden="true"><path d="M21 12a9 9 0 1 1-6.22-8.56"/></svg>',
    check: '<svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M20 6 9 17l-5-5"/></svg>',
  };

  const STYLE = `
    .mewtda-bis-button { display: flex; align-items: center; justify-content: center; gap: 8px; width: 100%; margin-top: 12px; padding: 14px 16px; border: 0; border-radius: 4px; background: var(--mewtda-bis-accent); color: #fff; font: inherit; font-size: 15px; cursor: pointer; }
    .mewtda-bis-button[hidden] { display: none; }
    .mewtda-bis-button--floating { position: fixed; right: 20px; bottom: 20px; z-index: 2147482999; width: auto; margin: 0; padding: 14px 22px; border-radius: 999px; box-shadow: 0 8px 24px rgba(0, 0, 0, .2); }
    @media (max-width: 640px) { .mewtda-bis-button--floating { left: 12px; right: 12px; bottom: 12px; border-radius: 8px; } }
    .mewtda-bis-overlay { position: fixed; inset: 0; z-index: 2147483000; display: flex; align-items: center; justify-content: center; padding: 16px; background: rgba(0, 0, 0, .55); }
    .mewtda-bis-modal { position: relative; width: 100%; max-width: 420px; overflow: hidden; border-radius: 16px; background: #fff; color: #111; font-family: inherit; }
    .mewtda-bis-body { display: grid; gap: 14px; padding: 24px 24px 20px; }
    .mewtda-bis-title { margin: 0 32px 4px 0; font-size: 18px; font-weight: 700; }
    .mewtda-bis-close { position: absolute; top: 18px; right: 18px; width: 28px; height: 28px; border: 1.5px solid #111; border-radius: 50%; background: none; font-size: 16px; line-height: 1; cursor: pointer; }
    .mewtda-bis-label { display: grid; gap: 6px; font-size: 14px; }
    .mewtda-bis-overlay .mewtda-bis-input { box-sizing: border-box; width: 100%; height: auto; margin: 0; padding: 12px 14px; border: 1px solid #c8c8c8; border-radius: 8px; background: #fff; box-shadow: none; color: #111; font-family: inherit; font-size: 16px; font-weight: 400; line-height: 1.4; letter-spacing: normal; text-indent: 0; }
    .mewtda-bis-overlay .mewtda-bis-input::placeholder { color: #9a9a9a; font-size: 16px; font-weight: 400; opacity: 1; }
    .mewtda-bis-overlay .mewtda-bis-input:focus { border-color: #111; outline: none; }
    .mewtda-bis-phone { display: flex; align-items: center; border: 1px solid #c8c8c8; border-radius: 8px; background: #fff; }
    .mewtda-bis-phone:focus-within { border-color: #111; }
    .mewtda-bis-prefix { padding: 0 12px 0 14px; border-right: 1px solid #e2e2e2; color: #777; font-size: 16px; line-height: 1.4; }
    .mewtda-bis-overlay .mewtda-bis-phone .mewtda-bis-input { border: 0; }
    .mewtda-bis-trap { position: absolute; left: -9999px; }
    .mewtda-bis-footer { padding: 20px 24px 24px; background: #f4f4f4; }
    .mewtda-bis-submit { display: flex; align-items: center; justify-content: center; gap: 8px; width: 100%; padding: 15px; border: 0; border-radius: 4px; background: var(--mewtda-bis-accent); color: #fff; font: inherit; font-size: 15px; cursor: pointer; }
    .mewtda-bis-submit:disabled { opacity: .8; cursor: wait; }
    .mewtda-bis-spinner { animation: mewtda-bis-spin .8s linear infinite; }
    @keyframes mewtda-bis-spin { to { transform: rotate(360deg); } }
    .mewtda-bis-message { margin: 0; font-size: 14px; }
    .mewtda-bis-message--error { color: #c62828; }
    .mewtda-bis-success { display: grid; justify-items: center; gap: 12px; padding: 40px 24px 24px; text-align: center; }
    .mewtda-bis-success__icon { display: flex; align-items: center; justify-content: center; width: 56px; height: 56px; border-radius: 50%; background: var(--mewtda-bis-accent); color: #fff; }
    .mewtda-bis-success .mewtda-bis-title { margin: 0; }
    .mewtda-bis-success .mewtda-bis-message { margin-bottom: 12px; color: #555; font-size: 15px; line-height: 1.5; }
  `;

  const SUCCESS = `
    <div class="mewtda-bis-success">
      <span class="mewtda-bis-success__icon">${ICONS.check}</span>
      <h2 class="mewtda-bis-title">Pronto!</h2>
      <p class="mewtda-bis-message">Avisaremos você por e-mail assim que o produto voltar ao estoque.</p>
      <button type="button" class="mewtda-bis-submit">Fechar</button>
    </div>
  `;

  const MODAL = `
    <div class="mewtda-bis-modal" role="dialog" aria-modal="true">
      <button type="button" class="mewtda-bis-close" aria-label="Fechar">&times;</button>
      <form novalidate>
        <div class="mewtda-bis-body">
          <h2 class="mewtda-bis-title"></h2>
          <label class="mewtda-bis-label">E-mail
            <input class="mewtda-bis-input" type="email" name="email" required autocomplete="email">
          </label>
          <label class="mewtda-bis-label">WhatsApp (opcional)
            <span class="mewtda-bis-phone">
              <span class="mewtda-bis-prefix">+55</span>
              <input class="mewtda-bis-input" type="tel" name="phone" inputmode="numeric" placeholder="(16) 99999-9999" autocomplete="tel-national">
            </span>
          </label>
          <select class="mewtda-bis-input" name="variant_id"></select>
          <input class="mewtda-bis-trap" type="text" name="website" tabindex="-1" autocomplete="off">
          <p class="mewtda-bis-message" hidden></p>
        </div>
        <div class="mewtda-bis-footer">
          <button type="submit" class="mewtda-bis-submit">${ICONS.bell}Quero ser avisado</button>
        </div>
      </form>
    </div>
  `;

  const DEFAULT_VARIANT_TITLE = "Default Title";

  const hasOptions = (product) => product.variants.some((variant) => variant.title !== DEFAULT_VARIANT_TITLE);

  const fetchJson = (url) => fetch(url).then((response) => (response.ok ? response.json() : Promise.reject(response)));

  const onlyDigits = (value) => value.replace(/\D/g, "");

  const maskPhone = (value) => {
    const digits = onlyDigits(value).slice(0, 11);

    if (digits.length <= 2) return digits.replace(/^(\d{1,2})/, "($1");
    if (digits.length <= 6) return digits.replace(/^(\d{2})(\d+)/, "($1) $2");
    if (digits.length <= 10) return digits.replace(/^(\d{2})(\d{4})(\d+)/, "($1) $2-$3");
    return digits.replace(/^(\d{2})(\d{5})(\d+)/, "($1) $2-$3");
  };

  const validPhone = (value) => [0, 10, 11].includes(onlyDigits(value).length);

  const absoluteUrl = (src) => (src?.startsWith("//") ? `https:${src}` : src);

  const productForm = (product) => {
    const ids = product.variants.map((variant) => String(variant.id));
    const forms = document.querySelectorAll('form[action*="/cart/add"]');

    return [...forms].find((form) => ids.includes(form.querySelector('[name="id"]')?.value));
  };

  const selectedVariant = (product, form) => {
    const id = Number(form?.querySelector('[name="id"]')?.value || new URLSearchParams(location.search).get("variant"));

    return product.variants.find((variant) => variant.id === id);
  };

  const initialVariant = (product) =>
    selectedVariant(product, productForm(product)) || product.variants.find((variant) => !variant.available);

  const placeButton = (button, form) => {
    button.classList.toggle("mewtda-bis-button--floating", !form);

    if (form && button.previousElementSibling !== form) form.after(button);
    if (!form && button.parentElement !== document.body) document.body.append(button);
  };

  const buildButton = (config) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = "mewtda-bis-button";
    button.innerHTML = `${ICONS.bell}<span></span>`;
    button.querySelector("span").textContent = config.button_text;
    return button;
  };

  const buildModal = (config, product, variant) => {
    const overlay = document.createElement("div");
    overlay.className = "mewtda-bis-overlay";
    overlay.innerHTML = MODAL;
    overlay.querySelector(".mewtda-bis-title").textContent = config.modal_title;

    const select = overlay.querySelector('[name="variant_id"]');
    select.hidden = !hasOptions(product);
    product.variants
      .filter((option) => !option.available)
      .forEach((option) => select.add(new Option(option.title, option.id, false, option.id === variant.id)));

    return overlay;
  };

  const alertPayload = (form, product, openedAt) => {
    const variant = product.variants.find((option) => option.id === Number(form.variant_id.value));

    return {
      token,
      website: form.website.value,
      elapsed_ms: Date.now() - openedAt,
      alert: {
        shopify_product_id: product.id,
        shopify_variant_id: variant.id,
        shopify_customer_id: window.__st?.cid,
        product_handle: product.handle,
        product_title: product.title,
        variant_title: hasOptions(product) ? variant.title : null,
        sku: variant.sku,
        price: variant.price / 100,
        image_url: absoluteUrl(variant.featured_image?.src || product.featured_image),
        email: form.email.value,
        phone: form.phone.value,
      },
    };
  };

  const showMessage = (overlay, text, error = false) => {
    const message = overlay.querySelector(".mewtda-bis-message");
    message.textContent = text;
    message.classList.toggle("mewtda-bis-message--error", error);
    message.hidden = false;
  };

  const setLoading = (button, loading) => {
    button.dataset.label ??= button.innerHTML;
    button.disabled = loading;
    button.innerHTML = loading ? `${ICONS.spinner}Enviando…` : button.dataset.label;
  };

  const showSuccess = (overlay, close) => {
    overlay.querySelector("form").outerHTML = SUCCESS;
    overlay.querySelector(".mewtda-bis-success .mewtda-bis-submit").addEventListener("click", close);
  };

  const submitAlert = async (overlay, product, openedAt, close) => {
    const form = overlay.querySelector("form");
    const submit = form.querySelector(".mewtda-bis-submit");

    if (!form.email.checkValidity()) return showMessage(overlay, "Informe um e-mail válido.", true);
    if (!validPhone(form.phone.value)) return showMessage(overlay, "Informe o WhatsApp com DDD.", true);

    setLoading(submit, true);
    const response = await fetch(`${API}/widget/back_in_stock/alerts`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(alertPayload(form, product, openedAt)),
    }).catch(() => null);
    setLoading(submit, false);

    if (response?.ok) return showSuccess(overlay, close);

    showMessage(overlay, "Não foi possível registrar agora. Tente novamente.", true);
  };

  const openModal = (config, product, variant) => {
    const overlay = buildModal(config, product, variant);
    const openedAt = Date.now();
    const close = () => overlay.remove();

    overlay.addEventListener("click", (event) => event.target === overlay && close());
    overlay.querySelector(".mewtda-bis-close").addEventListener("click", close);
    overlay.querySelector('[name="phone"]').addEventListener("input", (event) => {
      event.target.value = maskPhone(event.target.value);
    });
    overlay.querySelector("form").addEventListener("submit", (event) => {
      event.preventDefault();
      submitAlert(overlay, product, openedAt, close);
    });

    document.body.append(overlay);
    overlay.querySelector('[name="email"]').focus();
  };

  const injectStyle = (config) => {
    const style = document.createElement("style");
    style.textContent = STYLE;
    document.head.append(style);
    document.documentElement.style.setProperty("--mewtda-bis-accent", config.accent_color);
  };

  const start = (config, product) => {
    const button = buildButton(config);
    injectStyle(config);

    const sync = () => {
      const form = productForm(product);
      const variant = selectedVariant(product, form);

      placeButton(button, form);
      button.hidden = Boolean(form) && (!variant || variant.available);
    };

    button.addEventListener("click", () => openModal(config, product, initialVariant(product)));
    sync();
    setInterval(sync, SYNC_INTERVAL_MS);
  };

  Promise.all([
    fetchJson(`${API}/widget/back_in_stock/config?token=${encodeURIComponent(token)}`),
    fetchJson(`/products/${handle}.js`),
  ])
    .then(([config, product]) => {
      if (config.only_marked_products && !productEnabled) return;
      if (product.variants.some((variant) => !variant.available)) start(config, product);
    })
    .catch(() => {});
})();
