/* eslint react/no-unescaped-entities: 0 */
"use client";

import { useEffect, useMemo, useState, useTransition } from "react";
import { format } from "date-fns";
import { createSupabaseBrowserClient } from "@/lib/supabaseClient";
import type { Bottle, InventoryCountItem, MovementItem } from "@/lib/types";
import { useToast } from "@/components/Toaster";

type Props = { params: { id: string } };

export default function BottleDetailPage({ params }: Props) {
  const supabase = useMemo(createSupabaseBrowserClient, []);
  const { toast } = useToast();
  const [isPending, startTransition] = useTransition();

  const [bottle, setBottle] = useState<Bottle | null>(null);
  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [moveLocationId, setMoveLocationId] = useState("");
  const [moving, setMoving] = useState(false);
  const [counts, setCounts] = useState<InventoryCountItem[]>([]);
  const [movements, setMovements] = useState<MovementItem[]>([]);
  const [journalSubmitting, setJournalSubmitting] = useState(false);

  async function loadAll() {
    startTransition(async () => {
      const [{ data: b, error: e1 }] = await Promise.all([
        supabase
          .from("bottles")
          .select(
            "id, rfid_tag, brand, product, type, size_ml, price, status, tier, location_id, location_name, last_scanned, created_at, updated_at"
          )
          .eq("id", params.id)
          .single(),
      ]);
      if (e1) {
        toast({ title: "Failed to load bottle", description: e1.message, variant: "error" });
        return;
      }
      setBottle(b as Bottle);
      setMoveLocationId((b as Bottle).location_id ?? "");
      // recent counts
      const { data: cData } = await supabase
        .from("inventory_counts")
        .select("id, bottle_id, counted_at, location_id, location_name, method")
        .eq("bottle_id", params.id)
        .order("counted_at", { ascending: false })
        .limit(5);
      setCounts((cData as any as InventoryCountItem[]) ?? []);
      // recent movements
      const { data: mData } = await supabase
        .from("inventory_movements")
        .select("id, bottle_id, movement_type, from_location_id, to_location_id, notes, created_at")
        .eq("bottle_id", params.id)
        .order("created_at", { ascending: false })
        .limit(10);
      setMovements((mData as any as MovementItem[]) ?? []);
    });
  }

  useEffect(() => {
    loadAll();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [params.id]);

  async function onSave(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!bottle) return;
    setSaving(true);
    const form = new FormData(e.currentTarget);
    const payload = {
      brand: (form.get("brand") as string) || null,
      product: (form.get("product") as string) || null,
      type: (form.get("type") as string) || null,
      size_ml: form.get("size_ml") ? Number(form.get("size_ml")) : null,
      price: form.get("price") ? Number(form.get("price")) : null,
      status: (form.get("status") as string) || bottle.status,
      tier: (form.get("tier") as string) || null
    };
    try {
      const { error } = await supabase.from("bottles").update(payload as any).eq("id", bottle.id);
      if (error) throw error;
      toast({ title: "Saved", description: "Bottle updated", variant: "success" });
      await loadAll();
      setEditing(false);
    } catch (err: any) {
      toast({ title: "Save failed", description: err?.message ?? "Unknown error", variant: "error" });
    } finally {
      setSaving(false);
    }
  }

  async function onMoveLocation() {
    if (!bottle) return;
    setMoving(true);
    try {
      const payload = { location_id: moveLocationId || null };
      const { error } = await supabase.from("bottles").update(payload as any).eq("id", bottle.id);
      if (error) throw error;
      toast({ title: "Moved", description: "Location updated", variant: "success" });
      await loadAll();
    } catch (err: any) {
      toast({ title: "Move failed", description: err?.message ?? "Unknown error", variant: "error" });
    } finally {
      setMoving(false);
    }
  }

  async function onCreateMovement(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (!bottle) return;
    setJournalSubmitting(true);
    const form = new FormData(e.currentTarget);
    const movement_type = String(form.get("movement_type") || "input");
    const from_location_id = String(form.get("from_location_id") || "") || null;
    const to_location_id = String(form.get("to_location_id") || "") || null;
    const notes = String(form.get("notes") || "") || null;
    try {
      const { error } = await supabase.from("inventory_movements").insert({
        bottle_id: bottle.id,
        movement_type,
        from_location_id,
        to_location_id,
        notes
      });
      if (error) throw error;
      toast({ title: "Movement logged", variant: "success" });
      (e.currentTarget as HTMLFormElement).reset();
      await loadAll();
    } catch (err: any) {
      toast({
        title: "Failed to create movement",
        description: err?.message ?? "Unknown error",
        variant: "error"
      });
    } finally {
      setJournalSubmitting(false);
    }
  }

  if (!bottle) {
    return (
      <div className="container">
        <div className="card">
          <h2>Bottle Detail</h2>
          <p className="muted">{isPending ? "Loading…" : "Not found"}</p>
        </div>
      </div>
    );
  }

  return (
    <div className="container">
      <div className="card" style={{ marginBottom: 16 }}>
        <div className="toolbar">
          <div>
            <h2 style={{ marginBottom: 6 }}>Bottle Detail</h2>
            <div className="muted" style={{ fontSize: 13 }}>
              RFID <span className="mono">{bottle.rfid_tag}</span> • Last scanned{" "}
              {bottle.last_scanned ? format(new Date(bottle.last_scanned), "PP p") : "—"}
            </div>
          </div>
          <div>
            <button className="btn secondary" onClick={() => setEditing((v) => !v)}>
              {editing ? "Cancel" : "Edit"}
            </button>
          </div>
        </div>
        <form className="form" onSubmit={onSave}>
          <div className="grid-three">
            <div className="field-row">
              <label>Brand</label>
              <input name="brand" className="input" defaultValue={bottle.brand ?? ""} readOnly={!editing} />
            </div>
            <div className="field-row">
              <label>Product</label>
              <input name="product" className="input" defaultValue={bottle.product ?? ""} readOnly={!editing} />
            </div>
            <div className="field-row">
              <label>Type</label>
              <input name="type" className="input" defaultValue={bottle.type ?? ""} readOnly={!editing} />
            </div>
          </div>
          <div className="grid-three">
            <div className="field-row">
              <label>Size (ml)</label>
              <input
                name="size_ml"
                type="number"
                className="input"
                defaultValue={bottle.size_ml ?? ""}
                readOnly={!editing}
              />
            </div>
            <div className="field-row">
              <label>Price</label>
              <input
                name="price"
                type="number"
                step="0.01"
                className="input"
                defaultValue={bottle.price ?? ""}
                readOnly={!editing}
              />
            </div>
            <div className="field-row">
              <label>Tier</label>
              <input name="tier" className="input" defaultValue={bottle.tier ?? ""} readOnly={!editing} />
            </div>
          </div>
          <div className="grid-two">
            <div className="field-row">
              <label>Status</label>
              <select name="status" className="select" defaultValue={bottle.status ?? "active"} disabled={!editing}>
                <option value="active">Active</option>
                <option value="inactive">Inactive</option>
                <option value="unknown">Unknown</option>
              </select>
            </div>
            <div className="field-row">
              <label>Current Location</label>
              <input className="input" value={bottle.location_name ?? bottle.location_id ?? "—"} readOnly />
            </div>
          </div>
          {editing ? (
            <div className="actions">
              <button type="submit" className="btn" disabled={saving}>
                {saving ? "Saving…" : "Save"}
              </button>
            </div>
          ) : null}
        </form>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Move Location</h3>
        <div className="grid-two">
          <div className="field-row">
            <label>New Location UUID</label>
            <input
              className="input"
              value={moveLocationId}
              onChange={(e) => setMoveLocationId(e.target.value)}
              placeholder="Location UUID"
            />
          </div>
          <div className="field-row">
            <label style={{ visibility: "hidden" }}>Action</label>
            <button className="btn" onClick={onMoveLocation} disabled={moving}>
              {moving ? "Moving…" : "Move"}
            </button>
          </div>
        </div>
      </div>

      <div className="card" style={{ marginBottom: 16 }}>
        <h3 style={{ marginTop: 0 }}>Recent Counts</h3>
        <div className="table-wrap">
          <table className="table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Location</th>
                <th>Method</th>
              </tr>
            </thead>
            <tbody>
              {counts.length === 0 ? (
                <tr>
                  <td colSpan={3} className="empty">
                    No recent counts
                  </td>
                </tr>
              ) : (
                counts.map((c) => (
                  <tr key={c.id}>
                    <td>{format(new Date(c.counted_at), "PP p")}</td>
                    <td>{c.location_name ?? c.location_id ?? "—"}</td>
                    <td>{c.method ?? "—"}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      <div className="card">
        <div className="toolbar">
          <h3 style={{ margin: 0 }}>Movement Journal</h3>
        </div>
        <form className="form" onSubmit={onCreateMovement}>
          <div className="grid-three">
            <div className="field-row">
              <label>Type</label>
              <select name="movement_type" className="select" defaultValue="input">
                <option value="input">Input</option>
                <option value="output">Output</option>
                <option value="transfer">Transfer</option>
              </select>
            </div>
            <div className="field-row">
              <label>From Location (optional)</label>
              <input name="from_location_id" className="input" placeholder="UUID" />
            </div>
            <div className="field-row">
              <label>To Location (optional)</label>
              <input name="to_location_id" className="input" placeholder="UUID" />
            </div>
          </div>
          <div className="field-row">
            <label>Notes</label>
            <input name="notes" className="input" placeholder="Optional notes" />
          </div>
          <div className="actions">
            <button type="submit" className="btn" disabled={journalSubmitting}>
              {journalSubmitting ? "Creating…" : "Create Movement"}
            </button>
          </div>
        </form>
        <div className="table-wrap" style={{ marginTop: 12 }}>
          <table className="table">
            <thead>
              <tr>
                <th>Date</th>
                <th>Type</th>
                <th>From</th>
                <th>To</th>
                <th>Notes</th>
              </tr>
            </thead>
            <tbody>
              {movements.length === 0 ? (
                <tr>
                  <td colSpan={5} className="empty">
                    No movements
                  </td>
                </tr>
              ) : (
                movements.map((m) => (
                  <tr key={m.id}>
                    <td>{m.created_at ? format(new Date(m.created_at), "PP p") : "—"}</td>
                    <td>{m.movement_type}</td>
                    <td>{m.from_location_id ?? "—"}</td>
                    <td>{m.to_location_id ?? "—"}</td>
                    <td>{m.notes ?? "—"}</td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}


