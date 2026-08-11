export default function DashboardLoading() {
  return (
    <div className="loading-shell" role="status" aria-live="polite" aria-label="Memuat halaman">
      <div className="loading-heading" />
      <div className="loading-grid">
        <div className="loading-card" />
        <div className="loading-card" />
        <div className="loading-card" />
        <div className="loading-card" />
      </div>
      <div className="loading-panel" />
      <span style={{ position: "absolute", width: 1, height: 1, padding: 0, margin: -1, overflow: "hidden", clip: "rect(0, 0, 0, 0)", whiteSpace: "nowrap", border: 0 }}>
        Memuat data...
      </span>
    </div>
  );
}
