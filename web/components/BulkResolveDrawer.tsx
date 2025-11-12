"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import type { UnresolvedUnknown } from "@/lib/types";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";
import { useToast } from "./Toaster";

type Props = {
  open: boolean;
  rows: UnresolvedUnknown[];
  onClose: () => void;
  onResolved: (rfidTags: string[]) => void;
};

export function BulkResolveDrawer({ open, rows, onClose, onResolved }: Props) {
  const supabase = useMemo(createSupabaseBrowserClient, []);
  const { toast } = useToast();
  const [submitting, setSubmitting] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number }>({ done: 0, total: 0 });
  const titleId = useRef(`bulk-resolve-title-${Math.random().toString(36).slice(2)}`);
  const firstFieldRef = useRef<HTMLInputElement | null>(null);

  if (!open) return null;

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        onClose();
      }
    };
    document.addEventListener("keydown", handler);
    firstFieldRef.current?.focus();
    return () => document.removeEventListener("keydown", handler);
  }, [onClose]);

  async function onSubmit(formData: FormData) {
    setSubmitting(true);
    setProgress({ done: 0, total: rows.length });
    const sharedBrand = String(formData.get("brand") || "").trim();
    const sharedProduct = String(formData.get("product") || "").trim() || null;
    const sharedType = String(formData.get("type") || "").trim() || null;
    const sharedSize = String(formData.get("size") || "").trim() || null;
    const sharedPriceRaw = String(formData.get("price") || "").trim();
    const sharedPrice = sharedPriceRaw ? Number(sharedPriceRaw) : null;
    const sharedStatus = (String(formData.get("status") || "active") as "active" | "inactive" | "unknown");
    const createInitial = formData.get("create_initial_count") === "on";

    if (!sharedBrand) {
      toast({ title: "Missing brand", description: "Brand is required", variant: "error" });
      setSubmitting(false);
      return;
    }

    const resolvedTags: string[] = [];
    try {
      for (let i = 0; i < rows.length; i++) {
        const row = rows[i];
        const locationOverride = String(formData.get(`loc_${row.rfid_tag}`) || "").trim();
        const p_location_id = locationOverride || row.last_location_id || null;
        const { error } = await (supabase as any).rpc("resolve_unknown_epc", {
          p_organization_id: null,
          p_rfid_tag: row.rfid_tag,
          p_location_id,
          p_brand: sharedBrand,
          p_product: sharedProduct,
          p_type: sharedType,
          p_size: sharedSize,
          p_price: sharedPrice,
          p_status: sharedStatus,
          p_create_initial_count: createInitial
        });
        if (!error) {
          resolvedTags.push(row.rfid_tag);
        }
        setProgress({ done: i + 1, total: rows.length });
      }
      onResolved(resolvedTags);
      toast({
        title: "Bulk resolution complete",
        description: `Resolved ${resolvedTags.length}/${rows.length} items`,
        variant: resolvedTags.length === rows.length ? "success" : "default"
      });
      onClose();
    } catch (err: any) {
      toast({
        title: "Bulk resolve failed",
        description: err?.message ?? "Unknown error",
        variant: "error"
      });
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="drawer-backdrop" onClick={onClose} aria-hidden="true">
      <div
        className="drawer-panel"
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId.current}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="drawer-header">
          <h3 id={titleId.current}>Bulk Resolve ({rows.length})</h3>
          <button className="icon-btn" onClick={onClose} aria-label="Close">
            ×
          </button>
        </div>
        <form
          className="form"
          onSubmit={(e) => {
            e.preventDefault();
            onSubmit(new FormData(e.currentTarget));
          }}
        >
          <div className="grid-two">
            <div className="field-row">
              <label>Brand</label>
              <input name="brand" className="input" placeholder="Required" required ref={firstFieldRef} />
            </div>
            <div className="field-row">
              <label>Product</label>
              <input name="product" className="input" placeholder="Optional" />
            </div>
          </div>
          <div className="grid-three">
            <div className="field-row">
              <label>Type</label>
              <input name="type" className="input" placeholder="e.g., Vodka" />
            </div>
            <div className="field-row">
              <label>Size</label>
              <input name="size" className="input" placeholder="750ml" />
            </div>
            <div className="field-row">
              <label>Price</label>
              <input name="price" type="number" step="0.01" className="input" placeholder="19.99" />
            </div>
          </div>
          <div className="grid-two">
            <div className="field-row">
              <label>Status</label>
              <select name="status" className="select" defaultValue="active">
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
                <option value="unknown">Unknown</option>
              </select>
            </div>
            <div className="field-row">
              <label>Create initial count</label>
              <label className="checkbox">
                <input name="create_initial_count" type="checkbox" defaultChecked />
                <span>Day-1 count</span>
              </label>
            </div>
          </div>
          <div className="field-row">
            <label>Per-Row Location Overrides (optional)</label>
            <div className="table-wrap" style={{ maxHeight: 220 }}>
              <table className="table">
                <thead>
                  <tr>
                    <th>RFID</th>
                    <th>Location UUID</th>
                    <th>Hint</th>
                  </tr>
                </thead>
                <tbody>
                  {rows.map((r) => (
                    <tr key={r.rfid_tag}>
                      <td className="mono">{r.rfid_tag}</td>
                      <td>
                        <input
                          name={`loc_${r.rfid_tag}`}
                          className="input"
                          placeholder={r.last_location_id ?? ""}
                          defaultValue=""
                        />
                      </td>
                      <td className="muted">{r.last_location ?? r.last_location_name ?? "—"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
          <div className="actions">
            <div style={{ marginRight: "auto", color: "var(--muted)" }}>
              {submitting ? `Resolving ${progress.done}/${progress.total}…` : null}
            </div>
            <button type="button" className="btn secondary" onClick={onClose} disabled={submitting}>
              Cancel
            </button>
            <button type="submit" className="btn" disabled={submitting}>
              {submitting ? "Resolving…" : "Resolve Selected"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}


