from __future__ import annotations

from typing import Dict, List, Any, Iterable, Optional, Tuple
from datetime import datetime
from zoneinfo import ZoneInfo

import numpy as np
from sklearn.metrics.pairwise import cosine_similarity

TZ_UTC = ZoneInfo("UTC")


def _to_datetime(ts: Any) -> Optional[datetime]:
    if ts is None:
        return None
    try:
        dt = ts.to_datetime()
    except Exception:
        dt = ts
    if not isinstance(dt, datetime):
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=TZ_UTC)
    return dt.astimezone(TZ_UTC)

def _haversine_km(lat1, lng1, lat2, lng2) -> float:
    import math
    R = 6371.0
    p1 = math.radians(lat1); p2 = math.radians(lat2)
    dlat = math.radians(lat2 - lat1)
    dlng = math.radians(lng2 - lng1)
    a = math.sin(dlat/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dlng/2)**2
    return 2 * R * math.asin(math.sqrt(a))

def _recent_search_terms(user_doc: Any) -> List[str]:
    d = user_doc.to_dict() or {}
    arr = d.get("recentSearches") or []
    out: List[str] = []
    for x in arr:
        if isinstance(x, str):
            out.append(x)
        elif isinstance(x, dict):
            for k in ("text", "query", "term", "value", "category"):
                v = x.get(k)
                if isinstance(v, str) and v.strip():
                    out.append(v.strip())
                    break
    return [s.strip().lower() for s in out if isinstance(s, str) and s.strip()]

def _infer_categories_from_terms(terms: List[str], all_categories: List[str]) -> List[str]:
    cats_l = [(c, c.lower()) for c in all_categories if c and isinstance(c, str)]
    scores: Dict[str, int] = {}
    for t in terms:
        tl = t.lower()
        for orig, low in cats_l:
            if low in tl or tl in low:
                scores[orig] = scores.get(orig, 0) + 1
    return [c for c, _ in sorted(scores.items(), key=lambda x: x[1], reverse=True)[:2]]

def _decay_weight(event_dt: Optional[datetime], now_utc: datetime, half_life_days: float) -> float:
    if event_dt is None:
        return 1.0
    age_days = max(0.0, (now_utc - event_dt).total_seconds() / 86400.0)
    # exp(-ln(2) * age / half_life)
    return float(np.exp(-0.69314718056 * age_days / max(1e-6, half_life_days)))


def _extract_active_service_ids(services: Iterable[Any]) -> List[str]:
    out: List[str] = []
    for s in services:
        d = s.to_dict() or {}
        status = str(d.get("status", "")).lower()
        is_deleted = bool(d.get("isDeleted", False))
        if status == "active" and not is_deleted:
            out.append(s.id)
    return out


def _extract_seeker_ids(users: Iterable[Any]) -> List[str]:
    out: List[str] = []
    for u in users:
        d = u.to_dict() or {}
        if str(d.get("role") or "").lower() == "seeker":
            out.append(u.id)
    return out


def _service_rating(service_doc: Any) -> float:
    d = service_doc.to_dict() or {}
    for k in ("rating", "avgRating", "ratingAvg", "starsAvg"):
        v = d.get(k)
        if isinstance(v, (int, float)):
            return float(v)
    return 0.0


def build_recommendations(
    *,
    users,
    services,
    bookings,
    view_events: Optional[Iterable[Any]] = None,
    top_k: int = 5,
    # weights
    booking_weight: float = 3.0,
    view_weight: float = 0.25,
    # time decay
    half_life_days: float = 30.0,
    # cold-start threshold
    min_interactions: float = 1.0,
    # kNN neighbors
    knn_k: int = 40,
    user_main_loc: Optional[Dict[str, Tuple[float, float]]] = None,
) -> Dict[str, Dict[str, Any]]:
    """
    Hybrid recommender:
    - Item-based CF (cosine) when user has enough interactions
    - Cold-start content-based fallback otherwise

    Returns:
      { uid: { "serviceIds": [...], "algo": "item_cf"|"cold_start", "meta": {...} } }
    """
    service_ids = _extract_active_service_ids(services)
    seeker_ids = _extract_seeker_ids(users)

    # Track booked services per user
    booked_by_user: Dict[str, set] = {uid: set() for uid in seeker_ids}

    if not service_ids or not seeker_ids:
        return {}

    idx_service = {sid: j for j, sid in enumerate(service_ids)}
    idx_seeker = {uid: i for i, uid in enumerate(seeker_ids)}

    # interaction matrix (seekers x services)
    mat = np.zeros((len(seeker_ids), len(service_ids)), dtype=np.float32)

    # Track signal type separately (for explanation wording)
    mat_book = np.zeros_like(mat)
    mat_view = np.zeros_like(mat)

    now_utc = datetime.now(tz=TZ_UTC)

    # popularity prior (from interactions)
    service_pop = np.zeros((len(service_ids),), dtype=np.float32)

    # ---- bookings (strong signal) ----
    for b in bookings:
        d = b.to_dict() or {}
        uid = d.get("seekerId")
        sid = d.get("serviceId")
        if uid not in idx_seeker or sid not in idx_service:
            continue

        booked_by_user[uid].add(sid)

        dt_utc = _to_datetime(d.get("scheduledAt")) or _to_datetime(d.get("createdAt"))
        w = booking_weight * _decay_weight(dt_utc, now_utc, half_life_days)

        i = idx_seeker[uid]
        j = idx_service[sid]
        mat[i, j] += w
        mat_book[i, j] += w
        service_pop[j] += w

    # ---- views (weak signal) ----
    if view_events is not None:
        for v in view_events:
            d = v.to_dict() or {}
            uid = d.get("seekerId")
            sid = d.get("serviceId")
            if uid not in idx_seeker or sid not in idx_service:
                continue

            dt_utc = _to_datetime(d.get("viewedAt"))
            w = view_weight * _decay_weight(dt_utc, now_utc, half_life_days)

            i = idx_seeker[uid]
            j = idx_service[sid]
            mat[i, j] += w
            mat_view[i, j] += w
            service_pop[j] += w

    # avoid recommending items that have zero signal globally
    active_item_mask = service_pop > 0
    # if everything is zero, no CF possible
    if not np.any(active_item_mask):
        active_item_mask = np.ones_like(service_pop, dtype=bool)

    # compute item-item similarity
    mat_items = mat[:, active_item_mask]

    mat_items_book = mat_book[:, active_item_mask]
    mat_items_view = mat_view[:, active_item_mask]

    n_items = mat_items.shape[1]

    cf_possible = n_items >= 2

    def _precompute_item_knn(item_sim: np.ndarray, knn_k: int) -> Tuple[np.ndarray, np.ndarray]:
        """
        Returns:
          neigh_idx: (n_items, k) indices of top-k neighbors per item (descending sim)
          neigh_sim: (n_items, k) corresponding similarity values
        """
        n = item_sim.shape[0]
        knn_k = int(max(1, min(knn_k, n - 1)))

        # argsort descending per row, take top-k
        neigh_idx = np.argsort(item_sim, axis=1)[:, ::-1][:, :knn_k].astype(np.int32)  # (n, k)
        neigh_sim = np.take_along_axis(item_sim, neigh_idx, axis=1).astype(np.float32)  # (n, k)
        return neigh_idx, neigh_sim


    def _knn_scores_for_user(neigh_idx: np.ndarray, neigh_sim: np.ndarray, urow: np.ndarray) -> np.ndarray:
        """
        neigh_idx/neigh_sim: precomputed top-k neighbors per item
        urow: (n_items,) user interaction vector in the same masked item space
        Returns scores (n_items,)
        """
        n = urow.shape[0]
        scores = np.zeros((n,), dtype=np.float32)

        interacted_idx = np.where(urow > 0)[0]
        for i in interacted_idx:
            w = float(urow[i])
            scores[neigh_idx[i]] += w * neigh_sim[i]

        return scores

    def _explain_reco_for_item(
        *,
        target_j: int,
        urow: np.ndarray,
        neigh_idx: np.ndarray,
        neigh_sim: np.ndarray,
        masked_service_ids: List[str],
        urow_book: Optional[np.ndarray] = None,
        urow_view: Optional[np.ndarray] = None,
        top_n: int = 3,
    ) -> List[Dict[str, Any]]:
        """
        Explain why item target_j was recommended:
          contribution(i -> j) = urow[i] * sim(i, j)
        Only consider i that the user interacted with (urow[i] > 0)
        and where j appears in i's top-k neighbor list (consistent with scoring).
        """
        interacted = np.where(urow > 0)[0]
        contribs: List[Tuple[int, float, float, float]] = []

        for i in interacted:
            # Find if target_j is in i's neighbor list
            pos = np.where(neigh_idx[i] == target_j)[0]
            if pos.size == 0:
                continue
            p = int(pos[0])
            sim_ij = float(neigh_sim[i, p])
            if sim_ij <= 0:
                continue

            user_w = float(urow[i])
            c = user_w * sim_ij
            if c <= 0:
                continue

            contribs.append((int(i), float(c), float(sim_ij), float(user_w)))

        contribs.sort(key=lambda x: x[1], reverse=True)

        out: List[Dict[str, Any]] = []
        for i, c, sim_ij, user_w in contribs[:top_n]:
            # Determine interaction source
            book_w = float(urow_book[i]) if urow_book is not None else 0.0
            view_w = float(urow_view[i]) if urow_view is not None else 0.0

            if book_w > 0 or view_w > 0:
                src = "booked" if book_w >= view_w else "viewed"
            else:
                src = "activity"

            out.append(
                {
                    "becauseServiceId": masked_service_ids[i],
                    "becauseText": "",
                    "source": src,
                    "contribution": c,
                    "similarity": sim_ij,
                    "userWeight": user_w,
                }
            )
        return out

    def _apply_geo_radius_to_scores(
        *,
        uid: str,
        scores_vec: np.ndarray,
        radius_km: float,
    ) -> np.ndarray:
        """
        Soft geo-filter for CF ranking:
        - If user has main loc: remove services with known location outside radius
        - Services without location remain allowed
        """
        loc = (user_main_loc or {}).get(uid)
        if loc is None:
            return scores_vec

        u_lat, u_lng = loc
        out = scores_vec.copy()

        for j, sid in enumerate(masked_service_ids):
            sl = service_loc_all.get(sid)
            if sl is None:
                continue  # keep unknown-loc services
            dkm = _haversine_km(u_lat, u_lng, sl[0], sl[1])
            if dkm > radius_km:
                out[j] = -1e9
        return out

    neigh_idx = None
    neigh_sim = None

    if cf_possible:
        item_sim = cosine_similarity(mat_items.T)
        np.fill_diagonal(item_sim, 0.0)
        neigh_idx, neigh_sim = _precompute_item_knn(item_sim, knn_k)

    # map masked indices back
    masked_service_ids = [sid for sid, ok in zip(service_ids, active_item_mask) if ok]
    masked_idx_service = {sid: j for j, sid in enumerate(masked_service_ids)}

    # service ratings array aligned to masked_service_ids
    svc_by_id = {s.id: s for s in services}

    service_ids_all = service_ids[:]  # all active services (including 0-interaction)

    svc_dict_by_id: Dict[str, Dict[str, Any]] = {s.id: (s.to_dict() or {}) for s in services}

    # Rating (0..5)
    rating_by_sid: Dict[str, float] = {sid: _service_rating(svc_by_id[sid]) for sid in service_ids_all if sid in svc_by_id}

    # Popularity norm (0..1) based on service_pop, default 0 if no interactions
    pop_max = float(service_pop.max()) if float(service_pop.max()) > 0 else 0.0
    pop_norm_by_sid: Dict[str, float] = {}
    for sid in service_ids_all:
        j = idx_service.get(sid)
        if j is None or pop_max <= 0:
            pop_norm_by_sid[sid] = 0.0
        else:
            pop_norm_by_sid[sid] = float(service_pop[j] / (pop_max + 1e-6))

    # Categories across ALL services
    all_categories = sorted({
        str(svc_dict_by_id.get(sid, {}).get("category") or "").strip()
        for sid in service_ids_all
        if str(svc_dict_by_id.get(sid, {}).get("category") or "").strip()
    })

    # Locations across ALL services (for geo cold-start)
    service_loc_all: Dict[str, Tuple[float, float]] = {}
    for sid in service_ids_all:
        sd = svc_dict_by_id.get(sid, {})
        lat = sd.get("lat")
        lng = sd.get("lng")
        if isinstance(lat, (int, float)) and isinstance(lng, (int, float)):
            service_loc_all[sid] = (float(lat), float(lng))


    ratings = np.array([_service_rating(svc_by_id[sid]) for sid in masked_service_ids], dtype=np.float32)

    # popularity normalization for fallback scoring
    pop_masked = service_pop[active_item_mask]
    pop_norm = pop_masked / (pop_masked.max() + 1e-6)
    rating_norm = ratings / 5.0

    def cold_start_for_user(uid: str) -> List[str]:
        pref_cats: List[str] = []

        # category from views
        if view_events is not None:
            cat_count: Dict[str, float] = {}
            for v in view_events:
                d = v.to_dict() or {}
                if d.get("seekerId") != uid:
                    continue
                cat = str(d.get("category") or "").strip()
                if cat:
                    cat_count[cat] = cat_count.get(cat, 0.0) + 1.0
            pref_cats = [c for c, _ in sorted(cat_count.items(), key=lambda x: x[1], reverse=True)[:2]]

        # category from recentSearches if still empty
        if not pref_cats:
            # find the user doc object from `users` list
            user_doc = None
            for u in users:
                if u.id == uid:
                    user_doc = u
                    break

            if user_doc is not None:
                terms = _recent_search_terms(user_doc)
                pref_cats = _infer_categories_from_terms(terms, all_categories)

        # build candidate pool by category
        candidates = service_ids_all[:]
        if pref_cats:
            tmp: List[str] = []
            for sid in service_ids_all:
                sd = svc_dict_by_id.get(sid, {})
                cat = str(sd.get("category") or "").strip()
                if cat in pref_cats:
                    tmp.append(sid)
            if tmp:
                candidates = tmp

        # Geo filter: 8km -> 20km -> no geo
        loc = (user_main_loc or {}).get(uid)
        if loc is not None:
            u_lat, u_lng = loc

            def within(radius_km: float) -> List[str]:
                out: List[str] = []
                for sid in candidates:
                    sl = service_loc_all.get(sid)
                    if sl is None:
                        continue
                    dkm = _haversine_km(u_lat, u_lng, sl[0], sl[1])
                    if dkm <= radius_km:
                        out.append(sid)
                return out

            near8 = within(8.0)
            if near8:
                candidates = near8
            else:
                near20 = within(20.0)
                if near20:
                    candidates = near20

        if not candidates:
            candidates = service_ids_all[:]

        # score: rating + popularity + sentiment)
        scored: List[Tuple[str, float]] = []
        for sid in candidates:
            r = float(rating_by_sid.get(sid, 0.0)) / 5.0
            p = float(pop_norm_by_sid.get(sid, 0.0))

            sd = svc_dict_by_id.get(sid, {})
            sentiment = sd.get("sentiment_score")
            if sentiment is None:
                sentiment = sd.get("sentimentScore")

            sentiment_norm = 0.0
            if isinstance(sentiment, (int, float)):
                s = float(sentiment)
                s = max(-1.0, min(1.0, s))
                sentiment_norm = (s + 1.0) / 2.0

            score = float(
                0.50 * r +
                0.45 * p +
                0.05 * sentiment_norm
            )
            scored.append((sid, score))

        scored.sort(key=lambda x: x[1], reverse=True)
        return [sid for sid, _ in scored[:top_k]]


    out: Dict[str, Dict[str, Any]] = {}

    for uid in seeker_ids:
        urow_full = mat[idx_seeker[uid], :]
        user_signal = float(urow_full.sum())

        user_book_signal = float(mat_book[idx_seeker[uid], :].sum())
        user_view_signal = float(mat_view[idx_seeker[uid], :].sum())
        uniq_interactions = int(np.sum(urow_full > 0))

        # If only views and still sparse, stay in cold-start
        if user_book_signal <= 0 and uniq_interactions < 8:
            recs = cold_start_for_user(uid)
            out[uid] = {
                "serviceIds": recs,
                "algo": "cold_start",
                "meta": {
                    "userSignal": user_signal,
                    "bookSignal": user_book_signal,
                    "viewSignal": user_view_signal,
                    "uniqInteractions": uniq_interactions,
                    "reason": "view_only_sparse",
                },
            }
            continue

        # If cold-start / sparse user: use fallback
        if user_signal < min_interactions:
            recs = cold_start_for_user(uid)
            out[uid] = {
                "serviceIds": recs,
                "algo": "cold_start",
                "meta": {"userSignal": user_signal, "reason": "sparse_user"},
            }
            continue

        if (not cf_possible) or neigh_idx is None or neigh_sim is None:
            recs = cold_start_for_user(uid)
            out[uid] = {
                "serviceIds": recs,
                "algo": "cold_start",
                "meta": {"userSignal": user_signal, "reason": "cf_not_possible"},
            }
            continue

        # CF scoring on masked matrix
        urow = mat_items[idx_seeker[uid], :]  # masked item-space user vector
        urow_book = mat_items_book[idx_seeker[uid], :]
        urow_view = mat_items_view[idx_seeker[uid], :]

        raw_scores = _knn_scores_for_user(neigh_idx, neigh_sim, urow)

        # Exclude booked items only
        booked = booked_by_user.get(uid, set())
        for sid in booked:
            j = masked_idx_service.get(sid)
            if j is not None:
                raw_scores[j] = -1e9

        # If nothing meaningful → fallback
        if float(np.max(raw_scores)) <= -1e8:
            recs = cold_start_for_user(uid)
            out[uid] = {
                "serviceIds": recs,
                "algo": "cold_start",
                "meta": {"userSignal": user_signal, "reason": "no_cf_candidates"},
                "reasons": {},
            }
            continue

        # -----------------------------
        # Post-ranking (stabilize CF):
        # final = 0.75*CF + 0.15*rating + 0.10*pop
        # -----------------------------
        # Keep only positive CF for normalization
        cf_pos = np.clip(raw_scores, 0.0, None)
        cf_max = float(cf_pos.max())
        if cf_max <= 0:
            # CF exists but too weak after exclusions -> fallback
            recs = cold_start_for_user(uid)
            out[uid] = {
                "serviceIds": recs,
                "algo": "cold_start",
                "meta": {"userSignal": user_signal, "reason": "cf_zero_after_exclusion"},
                "reasons": {},
            }
            continue

        cf_norm = cf_pos / (cf_max + 1e-6)  # 0..1

        # rating_norm and pop_norm are aligned to masked_service_ids
        final_scores = (
            0.75 * cf_norm +
            0.15 * rating_norm +
            0.10 * pop_norm
        ).astype(np.float32)

        # Preserve hard exclusions (booked)
        for sid in booked:
            j = masked_idx_service.get(sid)
            if j is not None:
                final_scores[j] = -1e9

        # -----------------------------
        # Geo filter for CF:
        # 20km -> 40km -> no geo
        # -----------------------------
        geo_radius_used: Optional[float] = None
        if (user_main_loc or {}).get(uid) is not None:
            cand20 = _apply_geo_radius_to_scores(uid=uid, scores_vec=final_scores, radius_km=20.0)
            if float(np.max(cand20)) > -1e8:
                final_scores = cand20
                geo_radius_used = 20.0
            else:
                cand40 = _apply_geo_radius_to_scores(uid=uid, scores_vec=final_scores, radius_km=40.0)
                if float(np.max(cand40)) > -1e8:
                    final_scores = cand40
                    geo_radius_used = 40.0
                else:
                    geo_radius_used = None  # no geo filtering

        # -----------------------------
        # Pick top-k + build reasons
        # -----------------------------
        top_idx = np.argsort(final_scores)[::-1]

        recs: List[str] = []
        reasons: Dict[str, List[Dict[str, Any]]] = {}

        for j in top_idx:
            if len(recs) >= top_k:
                break
            if final_scores[j] <= -1e8:
                break

            sid_rec = masked_service_ids[int(j)]
            recs.append(sid_rec)

            # Explain using original CF neighbor contributions (urow + sim)
            expl = _explain_reco_for_item(
                target_j=int(j),
                urow=urow,
                urow_book=urow_book,
                urow_view=urow_view,
                neigh_idx=neigh_idx,
                neigh_sim=neigh_sim,
                masked_service_ids=masked_service_ids,
                top_n=3,
            )
            reasons[sid_rec] = expl

        # If still empty, fallback
        if not recs:
            recs = cold_start_for_user(uid)
            out[uid] = {
                "serviceIds": recs,
                "algo": "cold_start",
                "meta": {"userSignal": user_signal, "reason": "empty_after_postrank"},
                "reasons": {},
            }
            continue

        out[uid] = {
            "serviceIds": recs,
            "algo": "item_cf",
            "meta": {
                "userSignal": user_signal,
                "geoRadiusKm": geo_radius_used,
                "weights": {"cf": 0.75, "rating": 0.15, "pop": 0.10},
                "knnK": int(knn_k),
            },
            "reasons": reasons,
        }

    return out