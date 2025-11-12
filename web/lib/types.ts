export type UnresolvedUnknown = {
  id: string;
  organization_id: string;
  rfid_tag: string;
  last_seen_at: string; // ISO
  last_location_id?: string | null;
  last_location?: string | null; // fallback text from view
  last_location_name?: string | null; // alt fallback
  brand?: string | null;
  product?: string | null;
  product_id?: string | null;
  type?: string | null;
  size?: string | null;
  price?: number | null;
  seen_count?: number | null;
};

export type BottleListItem = {
  id: string;
  rfid_tag: string;
  brand: string | null;
  product: string | null;
  type: string | null;
  size_ml: number | null;
  location_id: string | null;
  location_name: string | null;
  status: "active" | "inactive" | "unknown" | null;
  last_scanned: string | null;
};

export type Bottle = {
  id: string;
  rfid_tag: string;
  brand: string | null;
  product: string | null;
  type: string | null;
  size_ml: number | null;
  price: number | null;
  status: "active" | "inactive" | "unknown" | null;
  tier: string | null;
  location_id: string | null;
  location_name: string | null;
  last_scanned: string | null;
  created_at: string | null;
  updated_at: string | null;
};

export type InventoryCountItem = {
  id: string;
  bottle_id: string;
  counted_at: string;
  location_id: string | null;
  location_name: string | null;
  method: string | null;
};

export type MovementItem = {
  id: string;
  bottle_id: string;
  movement_type: "input" | "output" | "transfer";
  from_location_id: string | null;
  to_location_id: string | null;
  notes: string | null;
  created_at: string | null;
};

export type CountsDailyRow = {
  id: string;
  counted_date: string; // yyyy-mm-dd
  location_id: string | null;
  location_name: string | null;
  brand: string | null;
  product: string | null;
  type: string | null;
  size: string | null;
  total: number | null;
};

export type MissingTodayRow = {
  bottle_id: string;
  rfid_tag: string;
  brand: string | null;
  product: string | null;
  type: string | null;
  size_ml: number | null;
  location_id: string | null;
  location_name: string | null;
};

export type DashboardCards = {
  active_bottles: number | null;
  unknown_last_24h: number | null;
  todays_counts: number | null;
};


