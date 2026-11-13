(() => {
  const SELECTOR = "select[data-custom-select]";

  const build = (select) => {
    if (select.dataset.enhanced) return;
    select.dataset.enhanced = "true";

    const wrapper = document.createElement("div");
    wrapper.className = "crm-select";
    wrapper.classList.toggle("crm-select--block", select.classList.contains("crm-select-block"));

    const button = document.createElement("button");
    button.type = "button";
    button.className = "crm-input crm-select__button";
    button.setAttribute("aria-haspopup", "listbox");
    button.setAttribute("aria-expanded", "false");
    const label = document.createElement("span");
    label.className = "crm-select__label";
    button.append(label);

    const menu = document.createElement("ul");
    menu.className = "crm-select__menu";
    menu.setAttribute("role", "listbox");
    menu.hidden = true;

    select.classList.add("crm-select__native");
    select.tabIndex = -1;
    select.setAttribute("aria-hidden", "true");
    select.before(wrapper);
    wrapper.append(button, menu, select);

    let active = -1;
    const items = () => Array.from(menu.children);

    const render = () => {
      menu.replaceChildren(...Array.from(select.options).map((option, index) => {
        const item = document.createElement("li");
        item.className = "crm-select__option";
        item.setAttribute("role", "option");
        item.dataset.index = index;
        item.setAttribute("aria-selected", String(option.selected));
        item.classList.toggle("is-selected", option.selected);
        item.classList.toggle("is-disabled", option.disabled);
        item.append(Object.assign(document.createElement("span"), { textContent: option.textContent }));
        if (option.selected && option.value) item.append(Object.assign(document.createElement("i"), { className: "fa-solid fa-check" }));
        return item;
      }));
      label.textContent = select.selectedOptions[0]?.textContent || "";
      label.classList.toggle("is-placeholder", !select.value);
    };

    const setActive = (index) => {
      active = Math.min(Math.max(index, 0), items().length - 1);
      items().forEach((item, position) => item.classList.toggle("is-active", position === active));
      items()[active]?.scrollIntoView({ block: "nearest" });
    };

    const open = () => {
      if (!menu.hidden) return;
      menu.hidden = false;
      button.setAttribute("aria-expanded", "true");
      setActive(select.selectedIndex);
    };

    const close = () => {
      menu.hidden = true;
      button.setAttribute("aria-expanded", "false");
    };

    const choose = (index) => {
      const option = select.options[index];
      if (!option || option.disabled) return;

      const changed = select.selectedIndex !== index;
      select.selectedIndex = index;
      render();
      close();
      button.focus();
      if (changed) select.dispatchEvent(new Event("change", { bubbles: true }));
    };

    button.addEventListener("click", () => (menu.hidden ? open() : close()));
    menu.addEventListener("click", (event) => {
      const item = event.target.closest(".crm-select__option");
      if (item) choose(Number(item.dataset.index));
    });
    menu.addEventListener("mousemove", (event) => {
      const item = event.target.closest(".crm-select__option");
      if (item) setActive(Number(item.dataset.index));
    });

    button.addEventListener("keydown", (event) => {
      if (["ArrowDown", "ArrowUp"].includes(event.key)) {
        event.preventDefault();
        if (menu.hidden) open();
        else setActive(active + (event.key === "ArrowDown" ? 1 : -1));
      } else if (event.key === "Home" || event.key === "End") {
        if (menu.hidden) return;
        event.preventDefault();
        setActive(event.key === "Home" ? 0 : items().length - 1);
      } else if (event.key === "Enter" || event.key === " ") {
        event.preventDefault();
        if (menu.hidden) open();
        else choose(active);
      } else if (event.key === "Escape" || event.key === "Tab") {
        close();
      }
    });

    select.addEventListener("change", render);
    wrapper.closeSelect = close;
    render();
  };

  const enhanceAll = (root) => root.querySelectorAll(SELECTOR).forEach(build);

  document.addEventListener("click", (event) => {
    document.querySelectorAll(".crm-select").forEach((wrapper) => {
      if (!wrapper.contains(event.target)) wrapper.closeSelect?.();
    });
  });

  new MutationObserver((mutations) => {
    mutations.forEach((mutation) => mutation.addedNodes.forEach((node) => {
      if (node.nodeType !== Node.ELEMENT_NODE) return;
      if (node.matches(SELECTOR)) build(node);
      enhanceAll(node);
    }));
  }).observe(document.body, { childList: true, subtree: true });

  enhanceAll(document);
})();
