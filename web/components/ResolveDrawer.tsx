/* eslint react/no-unescaped-entities: 0 */
"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { z } from "zod";
import type { UnresolvedUnknown } from "@/lib/types";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";
import { useToast } from "./Toaster";

const schema = z.object({
  brand: z.string().min(1, "Brand is required"),
  product: z.string().optional(),
  type: z.string().optional(),
  size: z.string().optional(),
  price: z.coerce.number().nonnegative().optional(),
  status: z.enum(["active", "inactive", "unknown"]).default("active"),
  location_id: z.string().uuid().optional(),
  create_initial_count: z.boolean().default(true)
});

type FormValues = z.infer<typeof schema>;

type Props = {
  open: boolean;
  row: UnresolvedUnknown | null;
  onClose: () => void;
  onResolved: (rfidTag: string) => void;
};

export function ResolveDrawer({ open, row, onClose, onResolved }: Props) {
  const supabase = useMemo(createSupabaseBrowserClient, []);
  const { toast } = useToast();
  const [submitting, setSubmitting] = useState(false);
  const titleId = useRef(`resolve-title-${Math.random().toString(36).slice(2)}`);
  const firstFieldRef = useRef<HTMLInputElement | null>(null);

  if (!open || !row) return null;

  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        e.preventDefault();
        onClose();
      }
    };
    document.addEventListener("keydown", handler);
    // focus first field on open
    firstFieldRef.current?.focus();
    return () => document.removeEventListener("keydown", handler);
  }, [onClose]);

  async function onSubmit(formData: FormData) {
    setSubmitting(true);
    try {
      const parsed = schema.parse({
        brand: formData.get("brand"),
        product: formData.get("product"),
        type: formData.get("type"),
        size: formData.get("size"),
        price: formData.get("price"),
        status: formData.get("status") ?? "active",
        location_id: formData.get("location_id") || row.last_location_id || undefined,
        create_initial_count: formData.get("create_initial_count") === "on"
      } as Record<string, unknown>);

      const { data, error } = await (supabase as any).rpc("resolve_unknown_epc", {
        p_organization_id: null, // RLS should scope; optionally pass if available from session/profile
        p_rfid_tag: row.rfid_tag,
        p_location_id: parsed.location_id ?? null,
        p_brand: parsed.brand,
        p_product: parsed.product ?? null,
        p_type: parsed.type ?? null,
        p_size: parsed.size ?? null,
        p_price: parsed.price ?? null,
        p_status: parsed.status,
        p_create_initial_count: parsed.create_initial_count
      });
      if (error) throw error;

      onResolved(row.rfid_tag);
      onClose();
    } catch (err: any) {
      const message = err?.message ?? "Failed to resolve";
      toast({ title: "Resolve failed", description: message, variant: "error" });
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
          <h3 id={titleId.current}>Resolve Unknown EPC</h3>
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
          <div className="field-row">
            <label>RFID Tag</label>
            <input className="input mono" value={row.rfid_tag} readOnly />
          </div>
          <div className="grid-two">
            <div className="field-row">
              <label>Brand</label>
              <input
                name="brand"
                className="input"
                defaultValue={row.brand ?? ""}
                placeholder="e.g., Tito's"
                required
                ref={firstFieldRef}
              />
            </div>
            <div className="field-row">
              <label>Product</label>
              <input
                name="product"
                className="input"
                defaultValue={row.product ?? ""}
                placeholder="Product name"
              />
            </div>
          </div>
          <div className="grid-three">
            <div className="field-row">
              <label>Type</label>
              <input name="type" className="input" defaultValue={row.type ?? ""} placeholder="Vodka" />
            </div>
            <div className="field-row">
              <label>Size</label>
              <input name="size" className="input" defaultValue={row.size ?? ""} placeholder="750ml" />
            </div>
            <div className="field-row">
              <label>Price</label>
              <input
                name="price"
                type="number"
                step="0.01"
                className="input"
                defaultValue={row.price ?? ""}
                placeholder="19.99"
              />
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
              <label>Location</label>
              <input
                name="location_id"
                className="input"
                defaultValue={row.last_location_id ?? ""}
                placeholder="Location UUID"
              />
            </div>
          </div>
          <div className="field-check">
            <label className="checkbox">
              <input name="create_initial_count" type="checkbox" defaultChecked />
              <span>Create initial count for today</span>
            </label>
          </div>
          <div className="actions">
            <button type="button" className="btn secondary" onClick={onClose} disabled={submitting}>
              Cancel
            </button>
            <button type="submit" className="btn" disabled={submitting}>
              {submitting ? "Resolving…" : "Resolve"}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}


