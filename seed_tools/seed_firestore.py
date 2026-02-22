#!/usr/bin/env python3
"""
KLServeLink Firestore Seeder (Medium demo)

Seeds:
- ~50 seekers (incl. your real seekerId)
- historical bookings in a configurable window
- service reviews under services/<serviceId>/reviews
- service_view_events (top-level) to simulate browsing behaviour with meaningful hourly counts

All seeded docs are tagged with:
- isSynthetic: true
- seedTag: <seedTag>

A seed run manifest is written to:
- seed_runs/<seedTag> with lists of created document paths for easy deletion.

Auth options:
A) gcloud ADC: `gcloud auth application-default login`
B) Service account key: set GOOGLE_APPLICATION_CREDENTIALS=/path/key.json

Usage example:
python seed_firestore.py --project klservelink \
  --provider-id EmBpgxscctZL1NnKDJ3Dv1tHyr32 \
  --real-seeker-id q1uMdJzEjgbQUcatEyGTcHPszBT2 \
  --primary-service-id T2ycb2fUxtT1DnpCMtDk \
  --bookings 300 --reviews 80 --views 15000
"""
from __future__ import annotations

import argparse
import dataclasses
import datetime as dt
import random
import string
from typing import Dict, List, Optional, Tuple

from google.cloud import firestore

KL_TZ = dt.timezone(dt.timedelta(hours=8))  # Asia/Kuala_Lumpur (no DST)


def _now_local() -> dt.datetime:
    return dt.datetime.now(tz=KL_TZ)


def _utc(d: dt.datetime) -> dt.datetime:
    if d.tzinfo is None:
        raise ValueError("Datetime must be timezone-aware")
    return d.astimezone(dt.timezone.utc)


def _server_ts():
    return firestore.SERVER_TIMESTAMP


def _slug(n: int = 10) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n))


@dataclasses.dataclass
class ServiceInfo:
    id: str
    provider_id: str
    name: str
    category: str
    price: float
    discount: float
    hourly_rate: float
    duration_minutes: int


def fetch_active_services(db: firestore.Client) -> List[ServiceInfo]:
    services: List[ServiceInfo] = []
    q = (
        db.collection("services")
        .where("status", "==", "active")
        .where("isDeleted", "==", False)
    )
    for doc in q.stream():
        d = doc.to_dict() or {}
        services.append(
            ServiceInfo(
                id=doc.id,
                provider_id=str(d.get("providerId", "")),
                name=str(d.get("name", "Service")),
                category=str(d.get("category", "General")),
                price=float(d.get("price", 0) or 0),
                discount=float(d.get("discount", 0) or 0),
                hourly_rate=float(d.get("hourlyRate", 0) or 0),
                duration_minutes=int(
                    (d.get("durationHours", 0) or 0) * 60 + (d.get("durationMins", 0) or 0)
                ),
            )
        )
    return services


def pick_services_by_category(services: List[ServiceInfo]) -> Dict[str, List[ServiceInfo]]:
    m: Dict[str, List[ServiceInfo]] = {}
    for s in services:
        m.setdefault(s.category.lower().strip() or "general", []).append(s)
    return m


def make_seekers(
    seed_tag: str, real_seeker_id: str, total_seekers: int = 50
) -> Tuple[List[Tuple[str, str]], List[Dict]]:
    first = [
        "Aina","Haziq","Amir","Siti","Wei","Jia","Daniel","Alicia","Farah","Irfan",
        "Nur","Hannah","Kumar","Arun","Yong","Mei","Zhi","Hakim","Syafiq","Maya",
    ]
    last = [
        "Tan","Lee","Lim","Wong","Ng","Ong","Chan","Chong","Teo","Goh","Loh","Kaur",
        "Singh","Hassan","Rahman","Ismail","Abdullah",
    ]

    def gen_name() -> str:
        return f"{random.choice(first)} {random.choice(last)}"

    synthetic_count = max(0, total_seekers - 1)
    synthetic_docs: List[Dict] = []
    seeker_list: List[Tuple[str, str]] = [(real_seeker_id, "Real Seeker")]

    for i in range(synthetic_count):
        uid = f"seed_{seed_tag}_{i:03d}"
        name = gen_name()
        seeker_list.append((uid, name))
        synthetic_docs.append(
            {
                "_docPath": f"users/{uid}",
                "role": "seeker",
                "name": name,
                "email": f"{uid}@example.com",
                "isSynthetic": True,
                "seedTag": seed_tag,
                "createdAt": _server_ts(),
                "updatedAt": _server_ts(),
            }
        )

    return seeker_list, synthetic_docs


def compute_amount(s: ServiceInfo, booked_minutes: int, scheduled_at_local: dt.datetime) -> Tuple[float, float]:
    included = max(0, s.duration_minutes)
    booked_minutes = max(booked_minutes, included)
    extra_minutes = max(0, booked_minutes - included)
    extra_hours = extra_minutes / 60.0

    discount = min(max(s.discount, 0.0), 100.0)
    floor = s.price * (1.0 - discount / 100.0)
    base = floor + extra_hours * s.hourly_rate

    rules_delta = 0.0

    wd = scheduled_at_local.isoweekday()  # 1..7
    if wd in (6, 7):
        if random.random() < 0.85:
            rules_delta += 0.20 * base

    if scheduled_at_local.hour >= 18:
        if random.random() < 0.60:
            rules_delta += 5.0

    total = max(0.0, base + rules_delta)
    total = round(total, 2)
    rules_delta = round(rules_delta, 2)
    return total, rules_delta


def build_day_weights(start: dt.date, end: dt.date, holiday_dates: List[dt.date]) -> List[Tuple[dt.date, float]]:
    cur = start
    out: List[Tuple[dt.date, float]] = []
    while cur <= end:
        wd = cur.isoweekday()
        w = 1.0
        if wd in (6, 7):
            w *= 2.6
        if cur in holiday_dates:
            w *= 3.5
        out.append((cur, w))
        cur += dt.timedelta(days=1)
    return out


def weighted_choice_date(weights: List[Tuple[dt.date, float]]) -> dt.date:
    dates = [d for d, _ in weights]
    w = [x for _, x in weights]
    return random.choices(dates, weights=w, k=1)[0]


def choose_hour() -> int:
    # bookings hours
    hours = [9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
    weights = [1, 3, 4, 4, 3, 3, 2, 2, 2, 3, 3, 2]
    return random.choices(hours, weights=weights, k=1)[0]


def choose_view_hour() -> int:
    # broader + more realistic browsing peaks (morning + lunch + evening)
    hours = list(range(7, 23))  # 7..22
    weights = []
    for h in hours:
        w = 1.0
        if 9 <= h <= 12:
            w *= 2.0
        if 12 <= h <= 14:
            w *= 1.8
        if 18 <= h <= 21:
            w *= 3.0
        if 15 <= h <= 17:
            w *= 1.3
        if h in (7, 8, 22):
            w *= 0.7
        weights.append(w)
    return random.choices(hours, weights=weights, k=1)[0]


def choose_minute() -> int:
    return random.choice([0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55])


def clamp5(mins: int) -> int:
    return int(round(mins / 5.0) * 5)


def gen_review_text(stars: int) -> str:
    positive = [
        "Very clean and professional. Arrived on time and did a great job.",
        "Friendly and efficient. Explained the process clearly.",
        "Great service! Fast response and quality work.",
        "Polite and careful with my house. Will book again.",
        "Excellent workmanship and reasonable price.",
    ]
    neutral = [
        "Overall okay. Could improve communication but work is acceptable.",
        "Service is fine. Not the fastest, but completed the task.",
        "Average experience. The result is acceptable.",
    ]
    negative = [
        "Arrived late and the work quality was not consistent.",
        "Not satisfied with the result. Needs improvement.",
        "Communication was poor and the job took longer than expected.",
        "Too expensive for the quality delivered.",
        "Had to request rework. Not a smooth experience.",
    ]
    if stars >= 5:
        return random.choice(positive)
    if stars == 4:
        return random.choice(positive + neutral)
    if stars == 3:
        return random.choice(neutral)
    if stars == 2:
        return random.choice(neutral + negative)
    return random.choice(negative)


def plan_user_clusters(categories: List[str]) -> List[List[str]]:
    cats = [c for c in categories if c]
    uniq: List[str] = []
    for c in cats:
        c2 = c.lower().strip()
        if c2 and c2 not in uniq:
            uniq.append(c2)

    if len(uniq) >= 6:
        return [
            uniq[0:2],
            uniq[2:4],
            uniq[4:6],
            uniq[0:1] + uniq[3:4],
            uniq[1:2] + uniq[5:6],
        ]
    return [
        ["cleaning", "plumbing"],
        ["electrical", "repair"],
        ["painting", "renovation"],
        ["moving", "delivery"],
        ["beauty", "wellness"],
    ]


def generate_view_events(
    *,
    total_views: int,
    services: List[ServiceInfo],
    svc_by_id: Dict[str, ServiceInfo],
    seeker_list: List[Tuple[str, str]],
    weights: List[Tuple[dt.date, float]],
    booking_docs: List[Dict],
    seed_tag: str,
    focus_provider_id: str,
    focus_provider_services: List[ServiceInfo],
    views_recent_days: int = 28,
    views_recent_share: float = 0.80,
) -> List[Dict]:
    """
    Generate view events with:
    - Bias toward last N days (views_recent_days, views_recent_share)
    - Converted journeys + burst sessions
    - Unconverted browsing biased to focus provider
    """
    view_docs: List[Dict] = []
    if total_views <= 0 or not services:
        return view_docs

    start_day = weights[0][0]
    end_day = weights[-1][0]

    # Recent-window weights (last N days)
    recent_days = max(1, int(views_recent_days))
    recent_start = end_day - dt.timedelta(days=recent_days - 1)
    weights_recent = [(d, w) for (d, w) in weights if d >= recent_start]
    if not weights_recent:
        weights_recent = weights

    def pick_weights_set() -> List[Tuple[dt.date, float]]:
        return weights_recent if random.random() < float(views_recent_share) else weights

    def random_time_in_window() -> dt.datetime:
        wset = pick_weights_set()
        day = weighted_choice_date(wset)
        return dt.datetime(day.year, day.month, day.day, choose_view_hour(), choose_minute(), tzinfo=KL_TZ)

    def random_time_in_recent() -> dt.datetime:
        day = weighted_choice_date(weights_recent)
        return dt.datetime(day.year, day.month, day.day, choose_view_hour(), choose_minute(), tzinfo=KL_TZ)

    # Split views between "converted journeys" vs browsing
    converted_share = 0.72
    converted_target = int(total_views * converted_share) if booking_docs else 0
    unconverted_target = total_views - converted_target

    # Prepare booking indices, and a "recent bookings" subset
    booking_idxs_all = list(range(len(booking_docs)))
    booking_idxs_recent: List[int] = []
    for i, b in enumerate(booking_docs):
        try:
            scheduled_local = b["scheduledAt"].astimezone(KL_TZ)
            if scheduled_local.date() >= recent_start:
                booking_idxs_recent.append(i)
        except Exception:
            pass
    if not booking_idxs_recent:
        booking_idxs_recent = booking_idxs_all

    # ---------- Converted journeys ----------
    if booking_docs and converted_target > 0:
        research_offsets = [72, 48, 36, 24]
        compare_offsets = [18, 12, 9, 6]
        decide_offsets = [3, 2, 1, 0]

        for _ in range(converted_target):
            # Bias booking choice toward recent window (so views also land in recent window)
            idx = random.choice(booking_idxs_recent) if random.random() < float(views_recent_share) else random.choice(booking_idxs_all)
            b = booking_docs[idx]

            scheduled_utc: dt.datetime = b["scheduledAt"]
            scheduled_local = scheduled_utc.astimezone(KL_TZ)

            stage = random.choices(
                ["research", "compare", "decide"],
                weights=[35, 40, 25],
                k=1
            )[0]

            if stage == "research":
                hours_before = random.choice(research_offsets)
            elif stage == "compare":
                hours_before = random.choice(compare_offsets)
            else:
                hours_before = random.choice(decide_offsets)

            viewed_local = (scheduled_local - dt.timedelta(hours=hours_before)).replace(
                minute=choose_minute(), second=0, microsecond=0
            )

            # Keep inside overall window
            if viewed_local.date() < start_day or viewed_local.date() > end_day:
                viewed_local = random_time_in_window()

            # If want "recent bias", and accidentally fell before recent_start, pull it into recent
            if random.random() < float(views_recent_share) and viewed_local.date() < recent_start:
                viewed_local = random_time_in_recent()

            # Mostly view the booked service; sometimes cross-shop another service by same provider (focus provider only)
            sid = str(b["serviceId"])
            provider_id = str(b["providerId"])
            chosen_service_id = sid

            if provider_id == focus_provider_id and focus_provider_services and random.random() < 0.18:
                chosen_service_id = random.choice(focus_provider_services).id

            svc = svc_by_id.get(chosen_service_id) or svc_by_id.get(sid)
            category = svc.category if svc else "General"

            view_docs.append(
                {
                    "serviceId": chosen_service_id,
                    "providerId": provider_id,
                    "category": category,
                    "seekerId": str(b["seekerId"]),
                    "viewedAt": _utc(viewed_local),
                    "eventType": "service_detail_view",
                    "isSynthetic": True,
                    "seedTag": seed_tag,
                    "seededAt": _server_ts(),
                }
            )

    # ---------- Unconverted browsing (sessions/bursts) ----------
    focus_share = 0.70 if focus_provider_services else 0.0

    remaining = unconverted_target
    while remaining > 0:
        session_size = random.choices(
            [1, 2, 3, 4, 5, 6],
            weights=[6, 14, 22, 20, 12, 6],
            k=1
        )[0]
        session_size = min(session_size, remaining)

        seeker_id, _ = random.choice(seeker_list)

        base_dt = random_time_in_window().replace(second=0, microsecond=0)

        target_focus = (random.random() < focus_share)
        if target_focus:
            s = random.choice(focus_provider_services)
        else:
            s = random.choice(services)

        burst_offsets_min = [0, 1, 2, 3, 5, 8, 13, 18, 25]
        for _ in range(session_size):
            delta_min = random.choice(burst_offsets_min)
            viewed_local = base_dt + dt.timedelta(minutes=delta_min)

            view_docs.append(
                {
                    "serviceId": s.id,
                    "providerId": s.provider_id,
                    "category": s.category,
                    "seekerId": seeker_id,
                    "viewedAt": _utc(viewed_local),
                    "eventType": "service_detail_view",
                    "isSynthetic": True,
                    "seedTag": seed_tag,
                    "seededAt": _server_ts(),
                }
            )

        remaining -= session_size

    random.shuffle(view_docs)
    return view_docs


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True, help="GCP project id: klservelink")
    ap.add_argument("--provider-id", required=True)
    ap.add_argument("--real-seeker-id", required=True)
    ap.add_argument("--primary-service-id", required=True)
    ap.add_argument("--bookings", type=int, default=300)
    ap.add_argument("--reviews", type=int, default=80)
    ap.add_argument("--views", type=int, default=15000)
    ap.add_argument("--views-recent-days", type=int, default=28)
    ap.add_argument("--views-recent-share", type=float, default=0.80)  # 80% views inside last 28 days
    ap.add_argument("--months", type=int, default=6, help="How many months of history to seed")
    ap.add_argument("--dry-run", action="store_true", help="Plan only, do not write")
    args = ap.parse_args()

    random.seed(42)

    db = firestore.Client(project=args.project)

    seed_tag = f"seed_medium_{_now_local().strftime('%Y%m%d_%H%M%S')}"
    end_day = (_now_local().date() - dt.timedelta(days=1))
    start_day = end_day - dt.timedelta(days=30 * args.months)

    holidays = [
        start_day + dt.timedelta(days=10),
        start_day + dt.timedelta(days=45),
        start_day + dt.timedelta(days=90),
        end_day - dt.timedelta(days=20),
        end_day - dt.timedelta(days=7),
    ]

    services = fetch_active_services(db)
    if not services:
        raise SystemExit("No active services found. Ensure services.status='active' and isDeleted=false.")

    svc_by_id: Dict[str, ServiceInfo] = {s.id: s for s in services}
    if args.primary_service_id not in svc_by_id:
        raise SystemExit(f"Primary service not found among active services: {args.primary_service_id}")

    by_cat = pick_services_by_category(services)
    all_categories = list(by_cat.keys())
    clusters = plan_user_clusters(all_categories)

    provider_services = [s for s in services if s.provider_id == args.provider_id]
    if not provider_services:
        print(f"WARNING: No active services found for provider {args.provider_id}.")

    seeker_list, synthetic_user_docs = make_seekers(seed_tag, args.real_seeker_id, total_seekers=50)

    weights = build_day_weights(start_day, end_day, holidays)
    provider_weight = 0.60 if provider_services else 0.0

    def pick_service_for_user(cluster_cats: List[str]) -> ServiceInfo:
        pool: List[ServiceInfo] = []
        for c in cluster_cats:
            pool += by_cat.get(c.lower().strip(), [])
        return random.choice(pool) if pool else random.choice(services)

    seeker_clusters: Dict[str, List[str]] = {}
    for uid, _name in seeker_list:
        seeker_clusters[uid] = random.choice(clusters)

    real_seeker_target = max(12, args.bookings // 20)
    real_seeker_booked = 0

    booking_docs: List[Dict] = []
    booking_indices_by_service: Dict[str, List[int]] = {}

    for i in range(args.bookings):
        day = weighted_choice_date(weights)
        hour = choose_hour()
        minute = choose_minute()
        scheduled_local = dt.datetime(day.year, day.month, day.day, hour, minute, tzinfo=KL_TZ)

        if real_seeker_booked < real_seeker_target:
            seeker_id, seeker_name = (args.real_seeker_id, "klax")
            real_seeker_booked += 1
        else:
            seeker_id, seeker_name = random.choice(seeker_list[1:])
        cluster = seeker_clusters[seeker_id]

        use_provider = provider_services and (random.random() < provider_weight)
        s = random.choice(provider_services) if use_provider else pick_service_for_user(cluster)

        base_mins = max(60, s.duration_minutes or 90)
        extra_mins = random.choice([0, 30, 60, 90, 120, 150, 180])
        booked_minutes = clamp5(base_mins + extra_mins)

        total_amount, rules_delta = compute_amount(s, booked_minutes, scheduled_local)
        hours = round(booked_minutes / 60.0, 2)

        doc = {
            "providerId": s.provider_id,
            "seekerId": seeker_id,
            "seekerName": seeker_name,
            "serviceId": s.id,
            "serviceName": s.name,
            "scheduledAt": _utc(scheduled_local),
            "status": "completed",
            "hours": hours,
            "totalAmount": total_amount,
            "rulesDelta": rules_delta,
            "pricingVerified": True,
            "pricingVersion": 1,
            "isReviewed": False,
            "isSynthetic": True,
            "seedTag": seed_tag,
            "seededAt": _server_ts(),
            "createdAt": _server_ts(),
            "updatedAt": _server_ts(),
        }
        booking_docs.append(doc)
        booking_indices_by_service.setdefault(s.id, []).append(i)

    primary_share = 0.62
    primary_reviews = int(round(args.reviews * primary_share))
    other_reviews = args.reviews - primary_reviews

    review_docs: List[Dict] = []

    def create_review_for_service(service_id: str) -> Optional[Dict]:
        idxs = booking_indices_by_service.get(service_id, [])
        if not idxs:
            return None
        bidx = random.choice(idxs)
        b = booking_docs[bidx]

        stars = random.choices([5, 4, 3, 2, 1], weights=[40, 28, 18, 9, 5], k=1)[0]
        text = gen_review_text(stars)

        scheduled_at_utc: dt.datetime = b["scheduledAt"]
        created_at = scheduled_at_utc + dt.timedelta(days=random.choice([1, 2, 3, 5, 7]))

        return {
            "serviceId": service_id,
            "providerId": b["providerId"],
            "seekerId": b["seekerId"],
            "seekerName": b["seekerName"],
            "bookingId": "",
            "stars": stars,
            "text": text,
            "verifiedJob": True,
            "createdAt": created_at,
            "isSynthetic": True,
            "seedTag": seed_tag,
            "seededAt": _server_ts(),
        }

    for _ in range(primary_reviews):
        r = create_review_for_service(args.primary_service_id)
        if r:
            review_docs.append(r)

    other_service_ids = [sid for sid in svc_by_id.keys() if sid != args.primary_service_id]
    random.shuffle(other_service_ids)
    for _ in range(other_reviews):
        candidates = [sid for sid in other_service_ids if booking_indices_by_service.get(sid)]
        target_sid = random.choice(candidates) if candidates else args.primary_service_id
        r = create_review_for_service(target_sid)
        if r:
            review_docs.append(r)

    view_docs = generate_view_events(
        total_views=args.views,
        services=services,
        svc_by_id=svc_by_id,
        seeker_list=seeker_list,
        weights=weights,
        booking_docs=booking_docs,
        seed_tag=seed_tag,
        focus_provider_id=args.provider_id,
        focus_provider_services=provider_services,
        views_recent_days=args.views_recent_days,
        views_recent_share=args.views_recent_share,
    )

    print("===== KLServeLink Seeding Plan =====")
    print(f"project: {args.project}")
    print(f"seedTag: {seed_tag}")
    print(f"history window: {start_day} .. {end_day} (local)")
    print(f"holiday spikes: {', '.join([d.isoformat() for d in holidays])}")
    print(f"synthetic seekers: {len(synthetic_user_docs)} (plus 1 real seeker)")
    print(f"bookings to create: {len(booking_docs)}")
    print(f"reviews to create: {len(review_docs)}")
    print(f"view events to create: {len(view_docs)}")
    print("====================================")

    if args.dry_run:
        print("Dry-run enabled: no writes performed.")
        return

    created_user_paths: List[str] = []
    created_booking_paths: List[str] = []
    created_review_paths: List[str] = []
    created_view_paths: List[str] = []

    # Write synthetic users
    batch = db.batch()
    op = 0
    for u in synthetic_user_docs:
        path = u.pop("_docPath")
        ref = db.document(path)
        batch.set(ref, u, merge=True)
        created_user_paths.append(path)
        op += 1
        if op >= 400:
            batch.commit()
            batch = db.batch()
            op = 0
    if op:
        batch.commit()

    # Write bookings (auto IDs)
    batch = db.batch()
    op = 0
    booking_ids: List[str] = []
    for b in booking_docs:
        ref = db.collection("bookings").document()
        batch.set(ref, b)
        booking_ids.append(ref.id)
        created_booking_paths.append(ref.path)
        op += 1
        if op >= 400:
            batch.commit()
            batch = db.batch()
            op = 0
    if op:
        batch.commit()

    booking_id_by_index = {i: booking_ids[i] for i in range(len(booking_ids))}

    # Write view events
    batch = db.batch()
    op = 0
    for v in view_docs:
        ref = db.collection("service_view_events").document()
        batch.set(ref, v)
        created_view_paths.append(ref.path)
        op += 1
        if op >= 400:
            batch.commit()
            batch = db.batch()
            op = 0
    if op:
        batch.commit()

    # Write reviews under services/<serviceId>/reviews/<autoId>
    batch = db.batch()
    op = 0
    for r in review_docs:
        service_id = r["serviceId"]
        idxs = booking_indices_by_service.get(service_id) or booking_indices_by_service.get(args.primary_service_id, [])
        if not idxs:
            continue
        bidx = random.choice(idxs)
        r["bookingId"] = booking_id_by_index[bidx]

        ref = db.collection("services").document(service_id).collection("reviews").document()
        batch.set(ref, r)
        created_review_paths.append(ref.path)
        op += 1
        if op >= 400:
            batch.commit()
            batch = db.batch()
            op = 0
    if op:
        batch.commit()

    # Mark bookings reviewed if they have a linked review
    reviewed_booking_ids = {r["bookingId"] for r in review_docs if r.get("bookingId")}
    batch = db.batch()
    op = 0
    for i, path in enumerate(created_booking_paths):
        bid = booking_ids[i]
        if bid in reviewed_booking_ids:
            batch.update(db.document(path), {"isReviewed": True})
            op += 1
            if op >= 400:
                batch.commit()
                batch = db.batch()
                op = 0
    if op:
        batch.commit()

    manifest = {
        "seedTag": seed_tag,
        "createdAt": _server_ts(),
        "note": "Medium demo seed for KLServeLink intelligent modules",
        "counts": {
            "users": len(created_user_paths),
            "bookings": len(created_booking_paths),
            "reviews": len(created_review_paths),
            "views": len(created_view_paths),
        },
        "paths": {
            "users": created_user_paths,
            "bookings": created_booking_paths,
            "reviews": created_review_paths,
            "views": created_view_paths,
        },
        "providerId_focus": args.provider_id,
        "realSeekerId_focus": args.real_seeker_id,
        "primaryServiceId_focus": args.primary_service_id,
        "windowLocal": {"start": start_day.isoformat(), "end": end_day.isoformat()},
    }
    db.collection("seed_runs").document(seed_tag).set(manifest)
    print(f"Seed complete. Manifest: seed_runs/{seed_tag}")


if __name__ == "__main__":
    main()
