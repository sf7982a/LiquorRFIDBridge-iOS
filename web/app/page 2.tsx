import Link from "next/link";

export default function HomePage() {
  return (
    <div className="container">
      <div className="card">
        <h2>Welcome</h2>
        <p>Select a module to begin.</p>
        <ul className="link-list">
          <li>
            <Link href="/reconciliation">Reconciliation</Link>
          </li>
          <li>
            <Link href="/bottles">Admin Bottles</Link>
          </li>
          <li>
            <Link href="/reporting">Reporting</Link>
          </li>
        </ul>
      </div>
    </div>
  );
}


