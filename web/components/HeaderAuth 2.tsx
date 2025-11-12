"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";

export function HeaderAuth() {
  const supabase = createSupabaseBrowserClient();
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    let mounted = true;
    (async () => {
      const { data } = await supabase.auth.getUser();
      if (!mounted) return;
      setEmail(data.user?.email ?? null);
    })();
    return () => {
      mounted = false;
    };
  }, [supabase]);

  if (!email) {
    return (
      <Link href="/auth/sign-in" className="btn secondary">
        Sign in
      </Link>
    );
  }

  return (
    <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
      <span className="muted" style={{ fontSize: 13 }}>
        {email}
      </span>
      <button
        className="btn secondary"
        onClick={async () => {
          await supabase.auth.signOut();
          window.location.href = "/auth/sign-in";
        }}
      >
        Sign out
      </button>
    </div>
  );
}


