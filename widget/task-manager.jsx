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

export const render = () => (
  <iframe
    src="http://localhost:8790/?widget&moldura"
    style={{ width: "100%", height: "100%", border: 0, display: "block", background: "transparent" }}
  />
);
