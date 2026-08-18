export default function AccountingLoading() {
  return (
    <section className="panel section-panel" aria-busy="true" aria-live="polite">
      <div className="panel-heading-row">
        <div>
          <p className="eyebrow">Finance & Accounting</p>
          <h3>Memuat Accounting Control Center…</h3>
          <p className="panel-subtitle">Menyiapkan data sesuai permission dan scope Anda.</p>
        </div>
        <span className="status-pill">LOADING</span>
      </div>
      <div className="check-list">
        <div className="check-item"><span>Access context</span><span className="check-state pending">CHECKING</span></div>
        <div className="check-item"><span>Accounting snapshot</span><span className="check-state pending">LOADING</span></div>
        <div className="check-item"><span>Control state</span><span className="check-state pending">LOADING</span></div>
      </div>
    </section>
  );
}
