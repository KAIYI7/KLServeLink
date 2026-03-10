from __future__ import annotations

from firebase_admin import firestore
from datetime import datetime, timedelta
from typing import Dict, List, Tuple
from zoneinfo import ZoneInfo

from app.firestore_client import get_db
from app.recommend import build_recommendations
from app.forecast import build_opportunity_index
from app.reviews import analyze_service_reviews

TZ_UTC = ZoneInfo("UTC")


def _load_user_main_locations(db) -> Dict[str, Tuple[float, float]]:
    out: Dict[str, Tuple[float, float]] = {}
    users = list(db.collection("users").where("role", "==", "seeker").stream())

    for u in users:
        addrs = list(db.collection("users").document(u.id).collection("addresses").stream())
        main = None
        for a in addrs:
            d = a.to_dict() or {}
            if d.get("isMain") is True:
                main = d
                break
        if main is None:
            if addrs:
                main = addrs[0].to_dict() or {}
            else:
                continue

        lat = main.get("lat")
        lng = main.get("lng")
        if isinstance(lat, (int, float)) and isinstance(lng, (int, float)):
            out[u.id] = (float(lat), float(lng))

    return out


def run_recommendations() -> Dict:
    db = get_db()
    recs_written = 0
    users = list(db.collection("users").stream())
    services = list(db.collection("services").where("status", "==", "active").stream())

    user_main_loc = _load_user_main_locations(db)
    cutoff = datetime.now(tz=TZ_UTC) - timedelta(days=180)

    bookings = list(
        db.collection("bookings")
        .where("scheduledAt", ">=", cutoff)
        .stream()
    )

    views = list(
        db.collection("service_view_events")
        .where("viewedAt", ">=", cutoff)
        .stream()
    )

    payloads = build_recommendations(
        users=users,
        services=services,
        bookings=bookings,
        view_events=views,
        top_k=5,
        knn_k=40,
        user_main_loc=user_main_loc,
        booking_weight=3.0,
        view_weight=0.25,
        half_life_days=30.0,
        min_interactions=1.0,
    )

    batch = db.batch()
    for uid, p in payloads.items():
        ref = db.collection("users").document(uid)
        batch.set(
            ref,
            {
                "recommendations": {
                    "serviceIds": p.get("serviceIds", []),
                    "algo": p.get("algo"),
                    "meta": p.get("meta", {}),
                    "reasons": p.get("reasons", {}),
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                }
            },
            merge=True,
        )
        recs_written += 1

    batch.commit()
    return {
        "users_updated": recs_written,
        "services_considered": len(services),
        "bookings_used": len(bookings),
        "views_used": len(views),
    }


def run_forecast(
        window_days: int = 28,
        horizon_days: int = 7,
        algo: str = "prophet",
) -> Dict:
    db = get_db()

    now_utc = datetime.now(tz=TZ_UTC)
    cutoff = now_utc - timedelta(days=window_days)

    algo_req = (algo or "prophet").lower().strip()

    # Providers
    users = list(db.collection("users").stream())
    provider_ids: List[str] = []
    for u in users:
        d = u.to_dict() or {}
        prov = d.get("provider", {})
        role = d.get("role") or prov.get("role")
        if role == "provider":
            provider_ids.append(u.id)

    # Services -> category map
    services = list(db.collection("services").where("status", "==", "active").stream())
    sid_to_cat: Dict[str, str] = {}
    for s in services:
        sd = s.to_dict() or {}
        cat = str(sd.get("category") or sd.get("categoryName") or "").strip()
        if cat:
            sid_to_cat[s.id] = cat

    # Marketplace-wide recent bookings
    bookings_recent = list(
        db.collection("bookings")
        .where("scheduledAt", ">=", cutoff)
        .stream()
    )

    # Provider-specific view events
    views_recent = list(
        db.collection("service_view_events")
        .where("viewedAt", ">=", cutoff)
        .stream()
    )

    views_by_provider: Dict[str, List] = {}
    for v in views_recent:
        d = v.to_dict() or {}
        pid = str(d.get("providerId") or "")
        if pid:
            views_by_provider.setdefault(pid, []).append(v)

    # Group provider bookings
    by_provider: Dict[str, List] = {}
    for b in bookings_recent:
        d = b.to_dict() or {}
        pid = str(d.get("providerId") or "")
        if not pid:
            continue
        by_provider.setdefault(pid, []).append(b)

    written = 0
    batch = db.batch()

    for pid in provider_ids:
        provider_rows = by_provider.get(pid, [])

        result = build_opportunity_index(
            provider_id=pid,
            provider_bookings=provider_rows,
            marketplace_bookings=bookings_recent,
            horizon_days=horizon_days,
            window_days=window_days,
            min_points=48,
            top_k=12,
            service_id_to_category=sid_to_cat,
            view_events=views_by_provider.get(pid, []),
            use_views_regressor=True,
            algo=algo_req,
        )

        slots_payload = [
            {
                "startAt": slot.get("startAt"),
                "score": slot.get("score"),
                "expectedBookings": slot.get("expectedBookings"),
                "expectedRevenue": slot.get("expectedRevenue"),
                "expectedViews": slot.get("expectedViews"),
                "expectedConversionRate": slot.get("expectedConversionRate"),
                "category": slot.get("category"),
            }
            for slot in (result.slots or [])
        ]

        payload = {
            "algo": result.algo_used,
            "slots": slots_payload,
            "categories": result.categories,
            "meta": result.meta,
            "updatedAt": firestore.SERVER_TIMESTAMP,
        }

        ref = db.collection("users").document(pid)

        # Production path:
        # for the main forecasting run, always write the latest hybrid / hybrid+Prophet result
        # to opportunity_index so cold-start providers still get usable slots.
        if algo_req in ("prophet", "auto", ""):
            batch.set(ref, {"opportunity_index": payload}, merge=True)
        else:
            # Explicit baseline / comparison path
            batch.set(
                ref,
                {"opportunity_index_baselines": {algo_req: payload}},
                merge=True,
            )

        written += 1

    batch.commit()
    return {
        "providers_updated": written,
        "bookings_used": len(bookings_recent),
        "views_used": len(views_recent),
        "window_days": window_days,
        "horizon_days": horizon_days,
        "algo_requested": algo_req,
    }


def run_reviews() -> Dict:
    db = get_db()
    services = list(db.collection("services").where("status", "==", "active").stream())

    updated = 0
    batch = db.batch()
    ops = 0

    def commit_batch():
        nonlocal batch, ops
        if ops > 0:
            batch.commit()
            batch = db.batch()
            ops = 0

    for s in services:
        score, keywords, reviews_analyzed = analyze_service_reviews(service_doc=s)

        ref = db.collection("services").document(s.id)

        if score is None and not keywords:
            batch.set(
                ref,
                {
                    "sentiment_score": firestore.DELETE_FIELD,
                    "top_keywords": firestore.DELETE_FIELD,
                    "reviewsAnalyzed": int(reviews_analyzed),
                    "sentimentUpdatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )
        else:
            batch.set(
                ref,
                {
                    "sentiment_score": float(score)
                    if score is not None
                    else firestore.DELETE_FIELD,
                    "top_keywords": keywords,
                    "reviewsAnalyzed": int(reviews_analyzed),
                    "sentimentUpdatedAt": firestore.SERVER_TIMESTAMP,
                },
                merge=True,
            )
            updated += 1

        ops += 1
        if ops >= 450:
            commit_batch()

    commit_batch()
    return {
        "services_updated": updated,
        "services_considered": len(services),
    }