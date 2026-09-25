// Widget do Übersicht: o Task Manager em modo compacto, preso na mesa.
// Posição e tamanho no className. O tema segue o do sistema (forçar: acrescentar &tema=claro ou &tema=escuro)
export const refreshFrequency = false;

export const className = `
  top: 48px;
  right: 32px;
  width: 360px;
  height: 760px;
  border-radius: 14px;
  overflow: hidden;
  box-shadow: 0 18px 50px rgba(0,0,0,.35);
`;

// A página avisa a altura da lista (postMessage) e o widget acompanha, até o teto de 900px.
const acompanharAltura = (el) => {
  if (!el || el.dataset.ok) return;
  el.dataset.ok = "1";
  window.addEventListener("message", (e) => {
    if (e.source === el.contentWindow && e.data && e.data.tmAltura) {
      el.parentElement.style.height = Math.min(e.data.tmAltura, 900) + "px";
    }
  });
};

export const render = () => (
  <iframe
    ref={acompanharAltura}
    src="http://localhost:8790/?widget&moldura"
    style={{ width: "100%", height: "100%", border: 0, display: "block", background: "transparent" }}
  />
);
