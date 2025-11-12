"use client";

import { useEffect, useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";

type Props = {
  allow: Array<"admin" | "manager" | "staff">;
  children: React.ReactNode;
};

export function RoleGuard({ allow, children }: Props) {
  const supabase = createSupabaseBrowserClient();
  const [role, setRole] = useState<"admin" | "manager" | "staff">("staff");
  const [ready, setReady] = useState(false);

  useEffect(() => {
    let mounted = true;
    (async () => {
      const { data } = await supabase.auth.getUser();
      const r =
        ((data.user?.user_metadata as any)?.role as "admin" | "manager" | "staff" | undefined) ??
        "staff";
      if (!mounted) return;
      setRole(r);
      setReady(true);
    })();
    return () => {
      mounted = false;
    };
  }, [supabase]);

  if (!ready) return null;
  if (!allow.includes(role)) return null;
  return <>{children}</>;
}


