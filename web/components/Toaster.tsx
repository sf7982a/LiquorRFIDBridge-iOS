"use client";

import { createContext, useContext, useMemo, useState } from "react";

type ToastVariant = "default" | "success" | "error";
type ToastItem = {
  id: string;
  title: string;
  description?: string;
  variant?: ToastVariant;
};

type ToastContextValue = {
  toast: (t: Omit<ToastItem, "id">) => void;
};

const ToastContext = createContext<ToastContextValue | null>(null);

export function Toaster({ children }: { children?: React.ReactNode }) {
  const [items, setItems] = useState<ToastItem[]>([]);
  const value = useMemo<ToastContextValue>(
    () => ({
      toast: ({ title, description, variant = "default" }) => {
        const id = Math.random().toString(36).slice(2);
        const next: ToastItem = { id, title, description, variant };
        setItems((prev) => [...prev, next]);
        setTimeout(() => {
          setItems((prev) => prev.filter((i) => i.id !== id));
        }, 3500);
      }
    }),
    []
  );
  return (
    <ToastContext.Provider value={value}>
      {children}
      <div className="toaster" role="status" aria-live="polite" aria-atomic="true">
        {items.map((t) => (
          <div key={t.id} className={`toast ${t.variant ?? "default"}`} role="alert">
            <div className="toast-title">{t.title}</div>
            {t.description ? <div className="toast-desc">{t.description}</div> : null}
          </div>
        ))}
      </div>
    </ToastContext.Provider>
  );
}

export function useToast() {
  const ctx = useContext(ToastContext);
  if (!ctx) {
    throw new Error("useToast must be used within <Toaster />");
  }
  return ctx;
}


