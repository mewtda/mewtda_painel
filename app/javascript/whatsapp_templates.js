// Prévia ao vivo do modelo de WhatsApp (balão) e botão para inserir {{1}}.
(function () {
  function init() {
    const form = document.getElementById('wt-form');
    if (!form || form.dataset.wtReady) return;
    form.dataset.wtReady = '1';

    const body = form.querySelector('[data-wt-body]');
    const field = (name) => form.querySelector(`[name="whatsapp_template[${name}]"]`);
    const example = field('body_example');
    const footer = field('footer');
    const buttonText = field('button_text');
    const exampleWrap = form.querySelector('[data-wt-example]');
    const count = form.querySelector('[data-wt-count]');
    const preview = (key) => document.querySelector(`[data-wt-preview-${key}]`);

    function render() {
      const name = (example.value || '').trim() || 'Maria';
      const text = body.value || '';
      preview('body').textContent = text.split('{{1}}').join(name);
      count.textContent = text.length;
      exampleWrap.hidden = !text.includes('{{1}}');
      preview('footer').textContent = footer.value;
      preview('footer').hidden = !footer.value.trim();
      preview('button-text').textContent = buttonText.value;
      preview('button').hidden = !buttonText.value.trim();
    }

    form.querySelector('[data-wt-insert]').addEventListener('click', () => {
      const start = body.selectionStart ?? body.value.length;
      const end = body.selectionEnd ?? body.value.length;
      body.value = body.value.slice(0, start) + '{{1}}' + body.value.slice(end);
      body.focus();
      body.selectionStart = body.selectionEnd = start + 5;
      render();
    });
    form.addEventListener('input', render);
    render();
  }

  document.addEventListener('DOMContentLoaded', init);
  document.addEventListener('turbo:load', init);
  init();
})();
