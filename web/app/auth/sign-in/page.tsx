/* eslint react/no-unescaped-entities: 0 */
"use client";

import { useState } from "react";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";
import { useToast } from "@/components/Toaster";

export default function SignInPage() {
  const supabase = createSupabaseBrowserClient();
  const { toast } = useToast();
  const [email, setEmail] = useState("");
  const [loading, setLoading] = useState(false);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    try {
      const { error } = await supabase.auth.signInWithOtp({
        email,
        options: {
          emailRedirectTo: typeof window !== "undefined" ? window.location.origin : undefined
        }
      });
      if (error) throw error;
      toast({
        title: "Check your email",
        description: "We sent a sign-in link to your inbox",
        variant: "success"
      });
    } catch (err: any) {
      toast({ title: "Sign-in failed", description: err?.message ?? "Unknown error", variant: "error" });
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="container">
      <div className="card" style={{ maxWidth: 420, margin: "40px auto" }}>
        <h2>Sign in</h2>
        <p className="muted" style={{ marginTop: -6 }}>
          Enter your email to receive a magic link
        </p>
        <form className="form" onSubmit={onSubmit} style={{ marginTop: 12 }}>
          <div className="field-row">
            <label>Email</label>
            <input
              type="email"
              className="input"
              placeholder="you@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </div>
          <div className="actions">
            <button className="btn" type="submit" disabled={loading}>
              {loading ? "Sending…" : "Send magic link"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}


