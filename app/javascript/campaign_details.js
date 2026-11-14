(() => {
  const dialog = document.getElementById("ec-details-dialog");
  if (!dialog) return;

  const body = dialog.querySelector("[data-details-body]");
  let request = 0;

  const show = (html) => { body.innerHTML = html; };
  const message = (text, loading = false) => {
    const paragraph = document.createElement("p");
    paragraph.className = "ec-details__message";
    if (loading) {
      const icon = document.createElement("i");
      icon.className = "fa-solid fa-circle-notch fa-spin";
      paragraph.append(icon, " ");
    }
    paragraph.append(text);
    body.replaceChildren(paragraph);
  };

  const open = async (url) => {
    const current = ++request;
    message("Carregando…", true);
    if (!dialog.open) dialog.showModal();
    try {
      const response = await fetch(url, { headers: { Accept: "text/html" } });
      if (!response.ok) throw new Error("load");
      const html = await response.text();
      if (current === request) show(html);
    } catch (error) {
      if (current === request) message("Não foi possível carregar os detalhes.");
    }
  };

  document.addEventListener("click", (event) => {
    const trigger = event.target.closest("[data-campaign-details]");
    if (trigger) {
      event.preventDefault();
      open(trigger.dataset.campaignDetails);
      return;
    }
    if (event.target.closest("[data-details-close]") || event.target === dialog) dialog.close();
  });
})();
