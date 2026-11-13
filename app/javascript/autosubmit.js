(() => {
  const TYPING_DELAY_MS = 450;
  const timers = new WeakMap();
  let controller;

  const regionIds = (form) => (form.dataset.liveRegions || "").split(",").map((id) => id.trim()).filter(Boolean);

  const setLoading = (ids, loading) =>
    ids.forEach((id) => document.getElementById(id)?.classList.toggle("is-live-loading", loading));

  async function refreshRegions(form) {
    const ids = regionIds(form);
    const url = new URL(form.action || location.href, location.href);
    url.search = new URLSearchParams(new FormData(form)).toString();

    controller?.abort();
    controller = new AbortController();
    form.classList.add("is-submitting");
    setLoading(ids, true);

    try {
      const response = await fetch(url, { headers: { Accept: "text/html" }, signal: controller.signal });
      if (!response.ok) throw new Error(response.status);

      const page = new DOMParser().parseFromString(await response.text(), "text/html");
      ids.forEach((id) => {
        const next = page.getElementById(id);
        if (next) document.getElementById(id)?.replaceWith(next);
      });
      history.replaceState(null, "", url);
      document.dispatchEvent(new CustomEvent("live:updated"));
      form.classList.remove("is-submitting");
    } catch (error) {
      if (error.name === "AbortError") return;

      setLoading(ids, false);
      form.submit();
    }
  }

  const submit = (form) => {
    if (!form) return;

    if (regionIds(form).length) return refreshRegions(form);

    form.classList.add("is-submitting");
    form.requestSubmit();
  };

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!regionIds(form).length) return;

    event.preventDefault();
    refreshRegions(form);
  });

  document.addEventListener("change", (event) => {
    const field = event.target;
    if (field.matches?.("[data-autosubmit]")) submit(field.form);
  });

  document.addEventListener("input", (event) => {
    const field = event.target;
    if (!field.matches?.("[data-autosubmit-typing]")) return;

    clearTimeout(timers.get(field));
    timers.set(field, setTimeout(() => submit(field.form), TYPING_DELAY_MS));
  });

  document.addEventListener("DOMContentLoaded", () => {
    const field = document.querySelector("[data-autosubmit-typing][autofocus]");
    field?.setSelectionRange(field.value.length, field.value.length);
  });
})();
