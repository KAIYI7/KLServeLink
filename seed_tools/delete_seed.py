#!/usr/bin/env python3
"""
KLServeLink Seed Deleter

Deletes everything created by seedTag(s) by reading:
- seed_runs/<seedTag>.paths.{users,bookings,reviews,views}

Usage:
# delete one seed
python delete_seed.py --project klservelink --seed-tag seed_medium_20260213_081441

# delete ALL seeds listed under seed_runs/
python delete_seed.py --project klservelink --all-seeds

# delete ALL seeds + also purge any remaining isSynthetic=true docs (in case a manifest is missing)
python delete_seed.py --project klservelink --all-seeds --purge-isSynthetic
"""
from __future__ import annotations

import argparse
from typing import Iterable, List, Optional, Dict, Set

from google.cloud import firestore


BATCH_LIMIT = 400


def chunked(iterable: List, n: int):
    for i in range(0, len(iterable), n):
        yield iterable[i:i + n]


def delete_paths(db: firestore.Client, doc_paths: List[str], label: str, dry_run: bool) -> None:
    if not doc_paths:
        return
    print(f"Deleting {len(doc_paths)} docs from {label}...")
    if dry_run:
        return
    for chunk in chunked(doc_paths, BATCH_LIMIT):
        batch = db.batch()
        for p in chunk:
            batch.delete(db.document(p))
        batch.commit()


def _batch_delete_refs(db: firestore.Client, refs: List[firestore.DocumentReference], label: str, dry_run: bool) -> None:
    if not refs:
        return
    print(f"Deleting {len(refs)} docs from {label}...")
    if dry_run:
        return
    for chunk in chunked(refs, BATCH_LIMIT):
        batch = db.batch()
        for r in chunk:
            batch.delete(r)
        batch.commit()


def recompute_service_ratings(db: firestore.Client, service_ids: Set[str], dry_run: bool) -> None:
    """Rebuild rating aggregates from remaining top-level reviews for the given services."""
    if not service_ids:
        return
    print(f"Recomputing service rating aggregates for {len(service_ids)} services...")
    if dry_run:
        return

    for service_id in sorted(service_ids):
        q = db.collection("reviews").where("serviceId", "==", service_id)
        count = 0
        ssum = 0.0
        stars = {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0}

        for doc in q.stream():
            d = doc.to_dict() or {}
            # Skip soft-deleted if present
            if d.get("isDeleted") is True:
                continue
            try:
                st_i = int(d.get("stars"))
            except Exception:
                continue
            if 1 <= st_i <= 5:
                count += 1
                ssum += float(st_i)
                stars[str(st_i)] = int(stars.get(str(st_i), 0)) + 1

        avg = (ssum / count) if count > 0 else 0.0
        db.collection("services").document(service_id).set(
            {
                "ratingCount": int(count),
                "ratingSum": float(ssum),
                "ratingAvg": float(avg),
                "rating": float(avg),
                "starCounts": stars,
                "reviewsAnalyzed": int(count),
                "updatedAt": firestore.SERVER_TIMESTAMP,
            },
            merge=True,
        )


def delete_by_seedtag_query(db: firestore.Client, seed_tag: str, dry_run: bool, recompute_ratings: bool) -> None:
    """Delete seeded docs by filtering seedTag==<seed_tag> across known collections.

    This is the safe fallback when:
    - seed_runs/<seed_tag> is missing (seed crashed before writing manifest)
    - seed_runs/<seed_tag> only stores sampled paths (pathsTruncated=true)
    """
    targets = [
        ("reviews (collection_group)", db.collection_group("reviews")),
        ("service_view_events", db.collection("service_view_events")),
        ("bookings", db.collection("bookings")),
        ("users", db.collection("users")),
    ]

    affected_service_ids: Set[str] = set()

    print("===== KLServeLink Seed Delete Plan (by query) =====")
    print(f"seedTag:  {seed_tag}")
    print("Targets:  reviews, service_view_events, bookings, users")
    print("===================================================")

    for label, colref in targets:
        refs: List[firestore.DocumentReference] = []
        q = colref.where("seedTag", "==", seed_tag)

        for doc in q.stream():
            if label == "reviews":
                try:
                    d = doc.to_dict() or {}
                    sid = d.get("serviceId")
                    if isinstance(sid, str) and sid:
                        affected_service_ids.add(sid)
                except Exception:
                    pass

            refs.append(doc.reference)
            if len(refs) >= BATCH_LIMIT:
                _batch_delete_refs(db, refs, label, dry_run)
                refs = []

        _batch_delete_refs(db, refs, label, dry_run)

    if recompute_ratings and affected_service_ids:
        recompute_service_ratings(db, affected_service_ids, dry_run)

def _normalize_star_counts(raw: object) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    if isinstance(raw, dict):
        for k, v in raw.items():
            ks = str(k)
            if ks in ("1", "2", "3", "4", "5"):
                counts[ks] = int(v) if isinstance(v, (int, float)) else 0
    for k in ("1", "2", "3", "4", "5"):
        counts.setdefault(k, 0)
    return counts


def rollback_service_rating_deltas(db: firestore.Client, deltas: Dict, dry_run: bool) -> None:
    """Best-effort rollback of rating aggregates on services/{serviceId}.

    Works if no other reviews were added/removed since the seed run.
    """
    if not deltas:
        return

    print(f"Rolling back service rating aggregates for {len(deltas)} services...")
    if dry_run:
        return

    for service_id, delta in deltas.items():
        ref = db.collection("services").document(service_id)
        tx = db.transaction()

        @firestore.transactional
        def _update(transaction: firestore.Transaction) -> None:
            snap = ref.get(transaction=transaction)
            if not snap.exists:
                return
            data = snap.to_dict() or {}

            old_count = int(data.get("ratingCount") or 0) if isinstance(data.get("ratingCount"), (int, float)) else 0
            old_sum = float(data.get("ratingSum") or 0.0) if isinstance(data.get("ratingSum"), (int, float)) else 0.0
            counts = _normalize_star_counts(data.get("starCounts"))

            d_count = int((delta or {}).get("count") or 0) if isinstance(delta, dict) else 0
            d_sum = float((delta or {}).get("sum") or 0.0) if isinstance(delta, dict) else 0.0
            d_stars = (delta or {}).get("stars") if isinstance(delta, dict) else {}

            new_count = max(0, old_count - d_count)
            new_sum = max(0.0, old_sum - d_sum)

            if isinstance(d_stars, dict):
                for k, dec in d_stars.items():
                    ks = str(k)
                    if ks in counts:
                        counts[ks] = max(0, int(counts.get(ks, 0)) - int(dec or 0))

            # If count hits 0, reset counts to zeros (avoid stale non-zero map)
            if new_count == 0:
                counts = {"1": 0, "2": 0, "3": 0, "4": 0, "5": 0}

            new_avg = (new_sum / new_count) if new_count > 0 else 0.0

            transaction.update(
                ref,
                {
                    "ratingCount": int(new_count),
                    "ratingSum": float(new_sum),
                    "ratingAvg": float(new_avg),
                    "rating": float(new_avg),
                    "starCounts": counts,
                    "reviewsAnalyzed": int(new_count),
                    "updatedAt": firestore.SERVER_TIMESTAMP,
                },
            )

        _update(tx)




def delete_seed_tag(db: firestore.Client, seed_tag: str, dry_run: bool, recompute_ratings: bool) -> None:
    manifest_ref = db.collection("seed_runs").document(seed_tag)
    snap = manifest_ref.get()

    # If the seed crashed before writing seed_runs/<seed_tag>, fall back to query deletes.
    if not snap.exists:
        print(f"WARNING: seed_runs/{seed_tag} not found. Falling back to deleting by seedTag query...")
        delete_by_seedtag_query(db, seed_tag, dry_run=dry_run, recompute_ratings=recompute_ratings)
        return

    m = snap.to_dict() or {}

    # Newer seeders may store only sampled paths to avoid Firestore index entry limits.
    if m.get("pathsTruncated") is True:
        print(f"INFO: seed_runs/{seed_tag} contains sampled paths (pathsTruncated=true). Deleting by seedTag query for full cleanup...")
        delete_by_seedtag_query(db, seed_tag, dry_run=dry_run, recompute_ratings=recompute_ratings)
        if dry_run:
            print("Dry-run enabled: manifest not deleted.")
            return
        manifest_ref.delete()
        print("Deleted seeded docs (by query) and manifest.")
        return

    paths: Dict = (m.get("paths") or {})

    users = list(paths.get("users") or [])
    providers = list(paths.get("providers") or [])
    services = list(paths.get("services") or [])
    bookings = list(paths.get("bookings") or [])
    reviews = list(paths.get("reviews") or [])
    views = list(paths.get("views") or [])
    service_rating_deltas = m.get("serviceRatingDeltas") or {}

    print("===== KLServeLink Seed Delete Plan =====")
    print(f"seedTag:  {seed_tag}")
    print(f"users:    {len(users)}")
    print(f"providers:{len(providers)}")
    print(f"services: {len(services)}")
    print(f"bookings: {len(bookings)}")
    print(f"reviews:  {len(reviews)}")
    print(f"views:    {len(views)}")
    print(f"services (rating rollback): {len(service_rating_deltas)}")
    print("========================================")

    # Delete order: reviews -> views -> bookings -> services -> users/providers
    delete_paths(db, reviews, "reviews", dry_run)
    rollback_service_rating_deltas(db, service_rating_deltas, dry_run)
    delete_paths(db, views, "service_view_events", dry_run)
    delete_paths(db, bookings, "bookings", dry_run)
    delete_paths(db, services, "services", dry_run)
    delete_paths(db, users, "users", dry_run)
    delete_paths(db, providers, "providers (users)", dry_run)

    if dry_run:
        print("Dry-run enabled: manifest not deleted.")
        return

    manifest_ref.delete()
    print("Deleted seeded docs and manifest.")



def purge_is_synthetic(db: firestore.Client, dry_run: bool) -> None:
    """
    Optional safety net: delete remaining docs with isSynthetic==True.
    This helps if a seed manifest is missing or incomplete.
    """
    print("===== Purge isSynthetic==True (optional) =====")
    if dry_run:
        print("Dry-run enabled: no purge deletes performed.")
        return

    def delete_query(q, label: str):
        # stream can be large; batch delete by references
        refs = []
        for doc in q.stream():
            refs.append(doc.reference)
            if len(refs) >= BATCH_LIMIT:
                batch = db.batch()
                for r in refs:
                    batch.delete(r)
                batch.commit()
                refs = []
        if refs:
            batch = db.batch()
            for r in refs:
                batch.delete(r)
            batch.commit()
        print(f"✅ Purged {label}")

    # Top-level collections
    delete_query(db.collection("users").where("isSynthetic", "==", True), "users")
    delete_query(db.collection("bookings").where("isSynthetic", "==", True), "bookings")
    delete_query(db.collection("service_view_events").where("isSynthetic", "==", True), "service_view_events")
    delete_query(db.collection("services").where("isSynthetic", "==", True), "services")

    # Reviews are subcollections: use collection group
    delete_query(db.collection_group("reviews").where("isSynthetic", "==", True), "reviews (collection_group)")
    print("=============================================")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--seed-tag", help="Delete a single seed tag")
    ap.add_argument("--all-seeds", action="store_true", help="Delete ALL seed runs found under seed_runs/")
    ap.add_argument("--purge-isSynthetic", action="store_true", help="Also delete any remaining docs with isSynthetic==True")
    ap.add_argument("--no-recompute-ratings", action="store_true", help="Skip rebuilding service rating aggregates after query-mode deletes")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    recompute_ratings = not args.no_recompute_ratings

    db = firestore.Client(project=args.project)

    if not args.seed_tag and not args.all_seeds:
        raise SystemExit("Provide either --seed-tag <tag> or --all-seeds")

    if args.all_seeds:
        seeds = list(db.collection("seed_runs").stream())
        seed_tags = [s.id for s in seeds]
        print(f"Found {len(seed_tags)} seed_runs docs.")
        for tag in seed_tags:
            delete_seed_tag(db, tag, args.dry_run, recompute_ratings)
    else:
        delete_seed_tag(db, args.seed_tag, args.dry_run, recompute_ratings)

    if args.purge_isSynthetic:
        purge_is_synthetic(db, args.dry_run)


if __name__ == "__main__":
    main()
