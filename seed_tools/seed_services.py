#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import math
import random
import string
from typing import Dict, List, Tuple

from google.cloud import firestore

KL_TZ = dt.timezone(dt.timedelta(hours=8))

CATEGORIES = [
    "Cleaning",
    "Plumbing",
    "Air-Conditioning",
    "Handyman & Repair",
    "Tutoring & Lessons",
]

BASE_LOC = (3.2070, 101.7160)  # ~Setapak/KL area


BUSINESS_NAMES = [
    "KL QuickFix", "Setapak HomeCare", "Wangsa Pro Services", "PJ Clean & Care",
    "Bangsar HandyHub", "Ampang Aircon Pros", "Cheras Fix-It", "Gombak Home Team",
    "Sri Rampai Solutions", "Mont Kiara HomeWorks", "Damansara Tutors", "Sunway Service Co.",
]

def _pick_business_name(used: set[str]) -> str:
    base = random.choice(BUSINESS_NAMES)
    name = base
    n = 2
    while name in used:
        n += 1
        name = f"{base} {n}"
    used.add(name)
    return name

SERVICE_TITLES = {
    "cleaning": [
        "Home Cleaning (Apartment)",
        "Deep Cleaning • 2 Bedrooms",
        "Move-in / Move-out Cleaning",
        "Kitchen & Bathroom Deep Clean",
        "Sofa & Mattress Cleaning",
        "Office Cleaning (Small Office)",
    ],
    "plumbing": [
        "Fix Leaking Tap / Pipe",
        "Toilet Unclog & Repair",
        "Water Heater Inspection",
        "Kitchen Sink Installation",
        "Pipe Leak Detection",
        "Shower & Drain Repair",
    ],
    "air-conditioning": [
        "Aircon Service (1 Unit)",
        "Aircon Chemical Wash (1 Unit)",
        "Aircon Gas Top-up & Check",
        "Aircon Troubleshooting",
        "Aircon Cleaning (2 Units)",
        "Split Unit Installation (Basic)",
    ],
    "handyman & repair": [
        "Furniture Assembly",
        "TV Wall Mounting",
        "Wall Drilling & Hanging",
        "Door / Cabinet Repair",
        "Minor Electrical Fix",
        "Curtain Rod Installation",
    ],
    "tutoring & lessons": [
        "Math Tuition (Secondary)",
        "English Writing Coaching",
        "Python Basics 1-on-1",
        "SPM Science Revision",
        "UI/UX Basics Lesson",
        "Microsoft Office Skills Coaching",
    ],
}

AREAS = [
    "Setapak", "Wangsa Maju", "Gombak", "Ampang", "Bangsar",
    "Sri Rampai", "Sentul", "Taman Melati", "KLCC", "Mont Kiara",
]

def _service_title(cat: str) -> str:
    key = cat.lower().strip()
    titles = SERVICE_TITLES.get(key, [f"{cat} Service"])
    title = random.choice(titles)
    if random.random() < 0.28:
        title = f"{title} • {random.choice(AREAS)}"
    return title

def _service_description(cat: str, _title: str) -> str:
    c = cat.lower()
    if "clean" in c:
        return (
            "Professional cleaning for condos and houses. Includes basic supplies and tidy-up. "
            "Flexible slots on weekdays and weekends."
        )
    if "plumb" in c:
        return (
            "On-site plumbing for common household issues (leaks, clogs, fittings). "
            "Clear explanation before work begins and neat cleanup after."
        )
    if "air" in c:
        return (
            "Air-conditioner servicing and troubleshooting. "
            "Recommended for weak cooling, smells, or noisy units. Includes basic checks."
        )
    if "handyman" in c or "repair" in c:
        return (
            "Handyman help for small repairs, installations, and assembly. "
            "Bring the right tools and keep your area clean when done."
        )
    if "tutor" in c or "lesson" in c:
        return (
            "1-on-1 lessons with structured notes and practice. "
            "Suitable for beginners or exam preparation. Remote or on-site depending on availability."
        )
    return "Reliable service with clear communication and flexible scheduling."


def _server_ts():
    return firestore.SERVER_TIMESTAMP


def _slug(n: int = 8) -> str:
    return "".join(random.choices(string.ascii_lowercase + string.digits, k=n))


def _jitter_km(lat: float, lng: float, radius_km: float) -> Tuple[float, float]:
    """
    Random point within radius_km (approx) around lat/lng.
    """
    # uniform over circle
    r = radius_km * math.sqrt(random.random())
    theta = 2 * math.pi * random.random()

    dlat = r * math.cos(theta) / 111.0
    dlng = r * math.sin(theta) / (111.0 * max(0.2, math.cos(math.radians(lat))))

    return lat + dlat, lng + dlng


def _defaults_for_category(cat: str) -> Dict:
    c = cat.lower()
    if "clean" in c:
        return {"price": (90, 220), "hourlyRate": (45, 80), "durMin": (60, 180)}
    if "plumb" in c:
        return {"price": (120, 350), "hourlyRate": (60, 120), "durMin": (60, 240)}
    if "air" in c:
        return {"price": (120, 300), "hourlyRate": (70, 140), "durMin": (60, 240)}
    if "handyman" in c or "repair" in c:
        return {"price": (100, 280), "hourlyRate": (55, 110), "durMin": (60, 240)}
    if "tutor" in c or "lesson" in c:
        return {"price": (60, 180), "hourlyRate": (40, 90), "durMin": (60, 180)}
    return {"price": (80, 200), "hourlyRate": (40, 90), "durMin": (60, 180)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--focus-provider-id", required=True, help="Real provider userId")
    ap.add_argument("--total-services", type=int, default=50)
    ap.add_argument("--extra-providers", type=int, default=8, help="Synthetic providers besides focus")
    ap.add_argument("--focus-provider-services", type=int, default=10, help="How many services assigned to focus provider")
    ap.add_argument("--radius-km", type=float, default=20.0)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    random.seed(args.seed)

    db = firestore.Client(project=args.project)

    seed_tag = f"seed_services_{dt.datetime.now(tz=KL_TZ).strftime('%Y%m%d_%H%M%S')}"
    print("seedTag:", seed_tag)

    # --- providers ---
    providers: List[str] = [args.focus_provider_id]
    for i in range(args.extra_providers):
        providers.append(f"seedprov_{seed_tag}_{i:02d}")


    # Give synthetic providers realistic business-style names
    used_names: set[str] = set()
    provider_name_by_id: Dict[str, str] = {args.focus_provider_id: "Your Provider"}
    for pid in providers[1:]:
        provider_name_by_id[pid] = _pick_business_name(used_names)
    # create provider user docs
    batch = db.batch()
    op = 0
    created_provider_paths: List[str] = []
    for pid in providers[1:]:
        ref = db.collection("users").document(pid)
        batch.set(
            ref,
            {
                "role": "provider",
                "name": provider_name_by_id.get(pid, "Service Provider"),
                "isSynthetic": True,
                "seedTag": seed_tag,
                "createdAt": _server_ts(),
                "updatedAt": _server_ts(),
                "provider": {"role": "provider"},
            },
            merge=True,
        )
        created_provider_paths.append(ref.path)
        op += 1
        if op >= 400:
            batch.commit()
            batch = db.batch()
            op = 0
    if op:
        batch.commit()

    # --- services ---
    total = int(args.total_services)
    focus_n = max(0, min(int(args.focus_provider_services), total))
    other_n = total - focus_n

    # provider assignment list: first focus_n for focus provider, remaining random from others
    service_providers = [args.focus_provider_id] * focus_n
    other_provider_pool = providers[1:] if len(providers) > 1 else [args.focus_provider_id]
    for _ in range(other_n):
        service_providers.append(random.choice(other_provider_pool))

    # round-robin categories
    cats = []
    for i in range(total):
        cats.append(CATEGORIES[i % len(CATEGORIES)])

    created_service_ids: List[str] = []
    created_service_paths: List[str] = []

    batch = db.batch()
    op = 0

    for i in range(total):
        cat = cats[i]
        pid = service_providers[i]

        title = _service_title(cat)

        base = _defaults_for_category(cat)
        price = round(random.uniform(*base["price"]), 2)
        hourly = round(random.uniform(*base["hourlyRate"]), 2)
        dur = random.randint(*base["durMin"])
        dur_h = dur // 60
        dur_m = dur % 60

        lat, lng = _jitter_km(BASE_LOC[0], BASE_LOC[1], args.radius_km)
        # Ratings start at 0; seed_firestore.py will populate aggregates from seeded reviews.
        rating_avg = 0.0
        rating_count = 0
        rating_sum = 0.0
        discount = random.choice([0, 0, 0, 5, 10, 15])

        # sentiment roughly [-1..1]
        sentiment = round(random.uniform(-0.2, 0.9), 3)

        ref = db.collection("services").document()
        doc = {
            "providerId": pid,
            "name": title,
            "category": cat,
            "status": "active",
            "isDeleted": False,
            "featured": bool(random.random() < 0.12),

            "price": price,
            "hourlyRate": hourly,
            "discount": float(discount),

            "durationHours": int(dur_h),
            "durationMins": int(dur_m),

            "lat": float(lat),
            "lng": float(lng),
            "geohash": "",

            "address": f"{random.choice(AREAS)}, Kuala Lumpur",

            "type": ("remote" if (cat == "Tutoring & Lessons" and random.random() < 0.45) else "onsite"),
            "autoLockTimeSlots": True,

            "photoUrls": [],
            "thumbnailUrl": None,

            "description": _service_description(cat, title),
            "rating": float(rating_avg),
            "ratingAvg": float(rating_avg),
            "ratingCount": int(rating_count),
            "ratingSum": float(rating_sum),
            "starCounts": {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0},

            "sentiment_score": float(sentiment),
            "top_keywords": random.sample(["reliable","fast","friendly","value","careful","professional","punctual","tidy"], k=3),
            "reviewsAnalyzed": int(rating_count),

            "pricingCaps": None,
            "pricingRules": [],

            "isSynthetic": True,
            "seedTag": seed_tag,
            "createdAt": _server_ts(),
            "updatedAt": _server_ts(),
            "sanitizedUpdatedAt": _server_ts(),
        }

        batch.set(ref, doc)
        created_service_ids.append(ref.id)
        created_service_paths.append(ref.path)

        op += 1
        if op >= 400:
            batch.commit()
            batch = db.batch()
            op = 0

    if op:
        batch.commit()

    # store manifest
    db.collection("seed_runs").document(seed_tag).set(
        {
            "seedTag": seed_tag,
            "type": "services_only",
            "createdAt": _server_ts(),
            "counts": {"providers": len(created_provider_paths), "services": len(created_service_paths)},
            "paths": {"providers": created_provider_paths, "services": created_service_paths},
            "focusProviderId": args.focus_provider_id,
        }
    )

    # Print a suggested primary service id belonging to focus provider
    suggested_primary = None
    q = db.collection("services").where("providerId", "==", args.focus_provider_id).where("status", "==", "active").limit(1)
    for doc in q.stream():
        suggested_primary = doc.id
        break

    print("\nCreated services:", len(created_service_ids))
    print("Suggested --primary-service-id (focus provider):", suggested_primary)
    print("Manifest:", f"seed_runs/{seed_tag}")


if __name__ == "__main__":
    main()
