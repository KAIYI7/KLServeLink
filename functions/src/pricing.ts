export type PricingRule = {
  id: string;
  label?: string;
  type: "percent" | "fixed";
  value: number;

  priority?: number;
  exclusiveGroup?: string;

  when?: {
    days?: number[];          // 1..7 (Mon..Sun)
    startHour?: number;       // 0..23
    endHour?: number;         // 0..23

    minDistanceKm?: number;
    maxDistanceKm?: number;

    minHours?: number;
    maxHours?: number;

    minLeadHours?: number;

    startDate?: string;
    endDate?: string;
  };
};

export type PricingCaps = {
  maxPercent?: number;
  maxFixed?: number;

  // advanced
  maxSurchargePercent?: number;
  maxDiscountPercent?: number;
  maxSurchargeFixed?: number;
  maxDiscountFixed?: number;
  minTotal?: number;
  maxTotal?: number;
};

export type PricingLine = { ruleId: string; label: string; amount: number, note?: string; };

export type PricingQuote = {
  baseFloor: number;
  hourlyRate: number;

  hours: number;          // booked hours (total)
  billableHours: number;  // extra hours beyond included hours

  hoursAmount: number;    // billableHours * hourlyRate
  rulesDelta: number;
  total: number;
  lines: PricingLine[];
};

function parseIsoDate(v: any): Date | null {
  if (v == null) return null;
  const s = String(v).trim();
  if (!s) return null;
  const parts = s.split("-");
  if (parts.length !== 3) return null;
  const y = Number(parts[0]);
  const m = Number(parts[1]);
  const d = Number(parts[2]);
  if (!Number.isFinite(y) || !Number.isFinite(m) || !Number.isFinite(d)) return null;
  return new Date(y, m - 1, d);
}

function applyExclusiveGroups(applicable: PricingRule[]): PricingRule[] {
  const nonGrouped: PricingRule[] = [];
  const grouped = new Map<string, PricingRule[]>();

  for (const r of applicable) {
    const g = String(r.exclusiveGroup ?? "").trim();
    if (!g) {
      nonGrouped.push(r);
      continue;
    }
    const arr = grouped.get(g) ?? [];
    arr.push(r);
    grouped.set(g, arr);
  }

  const picked: PricingRule[] = [];
  for (const [_g, arr] of grouped.entries()) {
    arr.sort((a, b) =>
      (Number(b.priority ?? 0) - Number(a.priority ?? 0)) ||
      (Math.abs(Number(b.value ?? 0)) - Math.abs(Number(a.value ?? 0))) ||
      String(a.id).localeCompare(String(b.id))
    );
    picked.push(arr[0]);
  }

  return [...nonGrouped, ...picked];
}

export function evaluatePricing(args: {
  floorPrice: number;
  hourlyRate: number;
  scheduledAt: Date;
  hours: number;                 // booked hours (total)
  includedHours?: number;        // package included hours
  distanceKm: number | null;
  rules: PricingRule[];
  caps?: PricingCaps;
}): PricingQuote {
  const { floorPrice, hourlyRate, scheduledAt, hours, distanceKm } = args;
  const rules = args.rules ?? [];

  const capNum = (k: keyof PricingCaps, fallback: number) => {
    const v: any = args.caps?.[k];
    return typeof v === "number" && Number.isFinite(v) ? v : fallback;
  };

  const maxPercentLegacy = capNum("maxPercent", 50);
  const maxFixedLegacy = capNum("maxFixed", 30);

  const maxSurchargePercent = capNum("maxSurchargePercent", maxPercentLegacy);
  const maxDiscountPercent  = capNum("maxDiscountPercent",  maxPercentLegacy);
  const maxSurchargeFixed   = capNum("maxSurchargeFixed",   maxFixedLegacy);
  const maxDiscountFixed    = capNum("maxDiscountFixed",    maxFixedLegacy);

  const minTotal = capNum("minTotal", 0);
  const maxTotal = capNum("maxTotal", 1e12);

  const includedH = Math.max(0, Number(args.includedHours ?? 0));
  const billableHours = Math.max(0, hours - includedH);

  const base = floorPrice + (billableHours * hourlyRate);
  const lines: PricingLine[] = [];

  // weekday: Sun=0..Sat=6 -> convert to 1..7 Mon..Sun
  const wd = scheduledAt.getDay();
  const weekdayKey = wd === 0 ? 7 : wd;

  const dayMatch = (when: any) => {
    const days: number[] | undefined = when?.days;
    if (!days || days.length === 0) return true;
    return days.includes(weekdayKey);
  };

  const timeMatch = (when: any) => {
    const sh = when?.startHour;
    const eh = when?.endHour;
    if (sh == null || eh == null) return true;
    const h = scheduledAt.getHours();

    // Normal: 9..18
    if (sh <= eh) return h >= sh && h <= eh;

    // Overnight: 22..6
    return h >= sh || h <= eh;
  };

  const hoursMatch = (when: any) => {
    const minH = when?.minHours;
    const maxH = when?.maxHours;
    if (typeof minH === "number" && hours < minH) return false;
    if (typeof maxH === "number" && hours > maxH) return false;
    return true;
  };

  const distanceMatch = (when: any) => {
    const minD = when?.minDistanceKm;
    const maxD = when?.maxDistanceKm;
    if (minD == null && maxD == null) return true;
    if (distanceKm == null) return false;
    if (typeof minD === "number" && distanceKm < minD) return false;
    if (typeof maxD === "number" && distanceKm > maxD) return false;
    return true;
  };

  const leadTimeMatch = (when: any) => {
    const minLeadHours = when?.minLeadHours;
    if (typeof minLeadHours !== "number") return true;
    const now = new Date();
    const diffH = (scheduledAt.getTime() - now.getTime()) / (1000 * 60 * 60);
    return diffH >= minLeadHours;
  };

  const dateRangeMatch = (when: any) => {
    const start = parseIsoDate(when?.startDate);
    const end = parseIsoDate(when?.endDate);
    if (!start && !end) return true;

    // compare by date-only
    const day = new Date(scheduledAt.getFullYear(), scheduledAt.getMonth(), scheduledAt.getDate());
    if (start) {
      const sDay = new Date(start.getFullYear(), start.getMonth(), start.getDate());
      if (day < sDay) return false;
    }
    if (end) {
      const eDay = new Date(end.getFullYear(), end.getMonth(), end.getDate());
      if (day > eDay) return false;
    }
    return true;
  };

  const matches = (when: any) =>
    dayMatch(when) &&
    timeMatch(when) &&
    hoursMatch(when) &&
    distanceMatch(when) &&
    leadTimeMatch(when) &&
    dateRangeMatch(when);

  const clampPercent = (v: number) => {
    if (v >= 0) return Math.min(maxSurchargePercent, Math.max(0, v));
    return Math.min(0, Math.max(-maxDiscountPercent, v));
  };

  const clampFixed = (v: number) => {
    if (v >= 0) return Math.min(maxSurchargeFixed, Math.max(0, v));
    return Math.min(0, Math.max(-maxDiscountFixed, v));
  };

  const appliesWhen = (when: any) => matches(when);
  // Filter by applicability
  const applicable = rules.filter(r => appliesWhen(r.when ?? {}));

  // Enforce exclusive groups
  const selected = applyExclusiveGroups(applicable);

  // Stable ordering for pricing + line items
  const sorted = [...selected].sort((a, b) =>
    (Number(b.priority ?? 0) - Number(a.priority ?? 0)) ||
    String(a.id).localeCompare(String(b.id))
  );

  let delta = 0;

  for (const r of sorted) {
    const id = String(r.id ?? "rule");
    const label = String(r.label ?? id);
    const type = r.type;
    const value = Number(r.value ?? 0);

    let amt = 0;
    let note: string | undefined;

    if (type === "percent") {
      const capped = clampPercent(value);
      amt = base * (capped / 100.0);

      if (Math.abs(capped - value) > 0.0001) {
        note = `Capped: ${value.toFixed(0)}% → ${capped.toFixed(0)}%`;
      }

    } else if (type === "fixed") {
      const capped = clampFixed(value);
      amt = capped;

      if (Math.abs(capped - value) > 0.0001) {
        note = `Capped: RM ${value.toFixed(2)} → RM ${capped.toFixed(2)}`;
      }

    } else {
      continue;
    }

    if (Math.abs(amt) > 0.0001) {
      delta += amt;
      lines.push({
        ruleId: id,
        label,
        amount: amt,
        note,
      });
    }
  }

  const rawTotal = base + delta;
  const total = Math.min(maxTotal, Math.max(minTotal, rawTotal));

  if (Math.abs(total - rawTotal) > 0.0001) {
    const direction = total > rawTotal ? "Raised" : "Lowered";
    lines.push({
      ruleId: "__TOTAL_CAP__",
      label: "Total adjusted by caps",
      amount: total - rawTotal,
      note: `${direction} to RM ${total.toFixed(2)}`,
    });
  }

  return {
    baseFloor: floorPrice,
    hourlyRate,
    hours,                 // booked hours (total)
    billableHours,
    hoursAmount: billableHours * hourlyRate,
    rulesDelta: delta,
    total,
    lines,
  };
}

export function haversineKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  const r = 6371.0;
  const d2r = (d: number) => (d * Math.PI) / 180.0;

  const dLat = d2r(lat2 - lat1);
  const dLon = d2r(lon2 - lon1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(d2r(lat1)) *
      Math.cos(d2r(lat2)) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return r * c;
}