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
from typing import Iterable, List, Optional, Dict

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


def delete_seed_tag(db: firestore.Client, seed_tag: str, dry_run: bool) -> None:
    manifest_ref = db.collection("seed_runs").document(seed_tag)
    snap = manifest_ref.get()
    if not snap.exists:
        print(f"WARNING: seed_runs/{seed_tag} not found (skipping).")
        return

    m = snap.to_dict() or {}
    paths: Dict = (m.get("paths") or {})

    users = list(paths.get("users") or [])
    bookings = list(paths.get("bookings") or [])
    reviews = list(paths.get("reviews") or [])
    views = list(paths.get("views") or [])

    print("===== KLServeLink Seed Delete Plan =====")
    print(f"seedTag:  {seed_tag}")
    print(f"users:    {len(users)}")
    print(f"bookings: {len(bookings)}")
    print(f"reviews:  {len(reviews)}")
    print(f"views:    {len(views)}")
    print("========================================")

    # Delete order: reviews -> views -> bookings -> users
    delete_paths(db, reviews, "reviews", dry_run)
    delete_paths(db, views, "service_view_events", dry_run)
    delete_paths(db, bookings, "bookings", dry_run)
    delete_paths(db, users, "users", dry_run)

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

    # Reviews are subcollections: use collection group
    delete_query(db.collection_group("reviews").where("isSynthetic", "==", True), "reviews (collection_group)")
    print("=============================================")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", required=True)
    ap.add_argument("--seed-tag", help="Delete a single seed tag")
    ap.add_argument("--all-seeds", action="store_true", help="Delete ALL seed runs found under seed_runs/")
    ap.add_argument("--purge-isSynthetic", action="store_true", help="Also delete any remaining docs with isSynthetic==True")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    db = firestore.Client(project=args.project)

    if not args.seed_tag and not args.all_seeds:
        raise SystemExit("Provide either --seed-tag <tag> or --all-seeds")

    if args.all_seeds:
        seeds = list(db.collection("seed_runs").stream())
        seed_tags = [s.id for s in seeds]
        print(f"Found {len(seed_tags)} seed_runs docs.")
        for tag in seed_tags:
            delete_seed_tag(db, tag, args.dry_run)
    else:
        delete_seed_tag(db, args.seed_tag, args.dry_run)

    if args.purge_isSynthetic:
        purge_is_synthetic(db, args.dry_run)


if __name__ == "__main__":
    main()
