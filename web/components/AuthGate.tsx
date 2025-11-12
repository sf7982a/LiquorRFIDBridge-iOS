"use client";

import { useEffect } from "react";
import { usePathname, useRouter } from "next/navigation";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";

export function AuthGate({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();

  useEffect(() => {
    let mounted = true;
    const supabase = createSupabaseBrowserClient();
    (async () => {
      const { data } = await supabase.auth.getSession();
      const isAuthRoute = pathname?.startsWith("/auth");
      if (!data.session && !isAuthRoute) {
        router.replace("/auth/sign-in");
      }
    })();
    return () => {
      mounted = false;
    };
  }, [pathname, router]);

  return <>{children}</>;
}


