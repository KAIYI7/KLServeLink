from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Dict, Iterable, List, Optional

import pandas as pd
from zoneinfo import ZoneInfo

TZ_LOCAL = ZoneInfo("Asia/Kuala_Lumpur")
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
    # Normalize to tz-aware UTC
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=TZ_UTC)
    return dt.astimezone(TZ_UTC)


def _floor_hour(dt: datetime) -> datetime:
    return dt.replace(minute=0, second=0, microsecond=0)


def _utc_to_local_naive(dt_utc: datetime) -> datetime:
    """Convert UTC-aware datetime to LOCAL wall-clock (tz removed) for Prophet training."""
    dt_local = dt_utc.astimezone(TZ_LOCAL)
    return dt_local.replace(tzinfo=None)


def _local_naive_to_utc(dt_local_naive: datetime) -> datetime:
    """Convert LOCAL wall-clock naive datetime to UTC-aware datetime for storage."""
    dt_local = dt_local_naive.replace(tzinfo=TZ_LOCAL)
    return dt_local.astimezone(TZ_UTC)

def _build_hourly_event_counts_local_naive(
    *,
    events: Iterable[Any],
    provider_id: str,
    time_field: str,
    start_utc: datetime,
    end_utc: datetime,
) -> pd.DataFrame:
    """
    Returns df: [ds (local naive hourly), cnt]
    """
    rows: List[datetime] = []
    for e in events:
        d = e.to_dict() if hasattr(e, "to_dict") else (e or {})
        if str(d.get("providerId") or "") != provider_id:
            continue
        dt_utc = _to_datetime(d.get(time_field))
        if dt_utc is None or dt_utc < start_utc or dt_utc > end_utc:
            continue
        rows.append(_utc_to_local_naive(_floor_hour(dt_utc)))

    if not rows:
        return pd.DataFrame(columns=["ds", "cnt"])

    ser = (
        pd.Series(1, index=pd.to_datetime(rows))
        .resample("H")
        .sum()
        .fillna(0)
        .astype(float)
    )
    df = ser.reset_index()
    df.columns = ["ds", "cnt"]
    return df


def _hour_of_week_mean(series_df: pd.DataFrame, value_col: str) -> pd.Series:
    """
    series_df: columns ["ds", value_col] where ds is datetime
    Returns a MultiIndex series keyed by (weekday, hour) -> mean(value_col)
    """
    tmp = series_df.copy()
    tmp["weekday"] = pd.to_datetime(tmp["ds"]).dt.weekday  # Mon=0
    tmp["hour"] = pd.to_datetime(tmp["ds"]).dt.hour
    return tmp.groupby(["weekday", "hour"])[value_col].mean()


def _fill_future_by_hour_of_week_mean(future: pd.DataFrame, mean_tbl: pd.Series, fallback: float) -> pd.Series:
    tmp = future.copy()
    tmp["weekday"] = pd.to_datetime(tmp["ds"]).dt.weekday
    tmp["hour"] = pd.to_datetime(tmp["ds"]).dt.hour
    # Map each row's (weekday,hour) to the mean table
    idx = list(zip(tmp["weekday"].tolist(), tmp["hour"].tolist()))
    out = [float(mean_tbl.get(k, fallback)) for k in idx]
    return pd.Series(out, index=future.index, dtype=float)

@dataclass
class OpportunityResult:
    slots: List[Dict[str, Any]]
    algo_used: str
    meta: Dict[str, Any]
    categories: List[Dict[str, Any]]


def build_opportunity_index(
    *,
    provider_id: str,
    bookings: Iterable[Any],
    horizon_days: int = 7,
    window_days: int = 28,
    min_points: int = 48,          # at least 2 days of hourly points
    top_k: int = 12,
    service_id_to_category: Optional[Dict[str, str]] = None,
    view_events: Optional[Iterable[Any]] = None,
    use_views_regressor: bool = True,
) -> OpportunityResult:
    """
    Production forecaster (Prophet primary). Forecasts hourly booking demand and scores
    expected profit = yhat_bookings * avg_realized_price.

    Returns slots: [{startAt: datetime(UTC), score: 0..100, expectedBookings, expectedRevenue}, ...]
    """
    now_utc = datetime.now(tz=TZ_UTC)
    start_utc = now_utc - timedelta(days=window_days)
    end_utc = now_utc

    # Collect booking hours (LOCAL naive) + realized prices
    hour_rows_local_naive: List[datetime] = []
    realized_prices: List[float] = []

    # Accumulate category revenue for "top categories" output
    cat_revenue: Dict[str, float] = {}

    for b in bookings:
        d = b.to_dict() if hasattr(b, "to_dict") else (b or {})
        if d.get("providerId") != provider_id:
            continue

        dt_utc = _to_datetime(d.get("scheduledAt"))
        if dt_utc is None or dt_utc < start_utc or dt_utc > end_utc:
            continue

        dt_hr_utc = _floor_hour(dt_utc)
        hour_rows_local_naive.append(_utc_to_local_naive(dt_hr_utc))

        status = str(d.get("status", "")).lower()
        if status == "completed":
            amt = d.get("totalAmount")
            if isinstance(amt, (int, float)) and amt > 0:
                realized_prices.append(float(amt))

                if service_id_to_category:
                    sid = str(d.get("serviceId") or "")
                    cat = service_id_to_category.get(sid, "").strip()
                    if cat:
                        cat_revenue[cat] = cat_revenue.get(cat, 0.0) + float(amt)

    # If too sparse, bail early (Fallback to heuristic)
    if len(hour_rows_local_naive) < 10:
        return OpportunityResult(slots=[], algo_used="none", meta={"reason": "too_few_rows"}, categories=[])

    # --- Build hourly series for Prophet (ds,y) ---
    ser = (
        pd.Series(1, index=pd.to_datetime(hour_rows_local_naive))
        .resample("H")
        .sum()
        .fillna(0)
        .astype(float)
    )
    df = ser.reset_index()
    df.columns = ["ds", "y"]

    # Ensure enough time coverage
    if len(df) < min_points:
        return OpportunityResult(
            slots=[],
            algo_used="none",
            meta={"reason": "too_few_points", "points": int(len(df))},
            categories=[],
        )

    avg_price = float(sum(realized_prices) / len(realized_prices)) if realized_prices else 1.0

    # Views regressor
    views_df = pd.DataFrame(columns=["ds", "views"])
    views_used = False

    if use_views_regressor and view_events is not None:
            v = _build_hourly_event_counts_local_naive(
                events=view_events,
                provider_id=provider_id,
                time_field="viewedAt",
                start_utc=start_utc,
                end_utc=end_utc,
            )
            if not v.empty:
                v = v.rename(columns={"cnt": "views"})

                if "views" not in v.columns:
                    v["views"] = 0.0
                v["views"] = v["views"].fillna(0.0).astype(float)

                # Merge onto df, fill missing with 0
                df = df.merge(v[["ds", "views"]], on="ds", how="left")
                df["views"] = df["views"].fillna(0.0).astype(float)

                # --- Debug: print views stats ---
                print(
                    "views_sum:", float(df["views"].sum()),
                    "views_mean:", float(df["views"].mean()),
                    "nonzero_hours:", int((df["views"] > 0).sum()),
                    "max_hour:", float(df["views"].max()),
                )

                # Only use regressor if it actually varies (avoid Prophet weirdness on constant column)
                if df["views"].sum() > 0 and df["views"].nunique() > 1:
                    views_df = df[["ds", "views"]].copy()
                    views_used = True
                else:
                    df = df.drop(columns=["views"], errors="ignore")
                    views_used = False

    future: Optional[pd.DataFrame] = None

    # --- Prophet primary ---
    try:
        from prophet import Prophet

        m = Prophet(
            weekly_seasonality=True,
            daily_seasonality=True,
            seasonality_mode="additive",
        )

        if views_used:
            m.add_regressor("views", standardize=False)

        # debug
        print("FIT columns:", df.columns.tolist(), "views_used:", views_used)

        m.fit(df)

        # debug
        if views_used:
            print("Regressor coef (views):", float(m.params["beta"][0][0]))

        # Find coefficient for the 'views' feature in the design matrix
        feat_names = m.train_component_cols.index.tolist()
        if "views" in feat_names:
            i = feat_names.index("views")
            views_coef = float(m.params["beta"][0, i])
            print("Views coef (proper):", views_coef)
        else:
            print("Views not found in feature names:", feat_names[:30], "...")


        future = m.make_future_dataframe(periods=horizon_days * 24, freq="H")

        if views_used:
            try:
                if (views_df is None) or views_df.empty or ("views" not in views_df.columns):
                    future["views"] = 0.0
                else:
                    mean_tbl = _hour_of_week_mean(views_df, "views")
                    fallback = float(views_df["views"].mean()) if len(views_df) else 0.0
                    future["views"] = _fill_future_by_hour_of_week_mean(future, mean_tbl, fallback)

                    # overwrite historical with actual views where available
                    future = future.merge(views_df[["ds", "views"]], on="ds", how="left", suffixes=("", "_actual"))
                    future["views"] = future["views_actual"].fillna(future["views"]).astype(float)
                    future = future.drop(columns=["views_actual"], errors="ignore")
            except Exception:
                future["views"] = 0.0
        else:
            views_used = False

        # debug
        print("PREDICT columns:", future.columns.tolist(), "views_used:", views_used)

        fc = m.predict(future)

        # debug
        #future0 = future.copy()
        #future0["views"] = 0.0
        #fc0 = m.predict(future0)

        #delta = (fc["yhat"] - fc0["yhat"]).describe()
        #print("Effect of views on yhat (delta):", delta.to_dict())

        cutoff = df["ds"].max()
        future_fc = fc[fc["ds"] > cutoff].copy()

        # Booking forecast
        yhat = future_fc["yhat"].clip(lower=0.0)

        # Expected profit proxy
        expected_revenue = yhat * avg_price

        if expected_revenue.max() <= 0:
            return OpportunityResult(slots=[], algo_used="prophet", meta={"reason": "zero_forecast"}, categories=[])

        future_fc["expectedBookings"] = yhat
        future_fc["expectedRevenue"] = expected_revenue
        future_fc["score"] = (expected_revenue / expected_revenue.max()) * 100.0

        # Attach future views + conversion rate
        #if views_used:
        #    if "views" not in future_fc.columns:
        #        v_future = future[future["ds"] > cutoff][["ds", "views"]].copy()
        #        future_fc = future_fc.merge(v_future, on="ds", how="left", suffixes=("", "_future"))
#
        #        # If merge produced views_future, normalize back to 'views'
        #        if "views_future" in future_fc.columns and "views" not in future_fc.columns:
        #            future_fc["views"] = future_fc["views_future"]
        #    else:
        #        future_fc["views"] = future_fc["views"].astype(float)
        #        v_future_raw = future.loc[future["ds"] > cutoff, ["ds", "views"]].copy()
        #        v_future_raw = v_future_raw.rename(columns={"views": "views_raw"})
#
        #    if "views" not in future_fc.columns:
        #        if "views_x" in future_fc.columns:
        #            future_fc["views"] = future_fc["views_x"]
        #        elif "views_y" in future_fc.columns:
        #            future_fc["views"] = future_fc["views_y"]
#
        #    future_fc["views"] = future_fc["views"].fillna(0.0).astype(float).clip(lower=0.0)
         #   future_fc["expectedViews"] = future_fc["views"]
#
         #   # Add floor so denom isn't near zero
        #    views_floor = 1.0
#
        #    denom = future_fc["expectedViews"] + views_floor
        #    future_fc["expectedConversionRate"] = (
        #        (future_fc["expectedBookings"] / denom).clip(lower=0.0, upper=1.0)
        #    )
        #else:
        #    future_fc["expectedViews"] = None
        #    future_fc["expectedConversionRate"] = None

        # Attach future views (RAW) + conversion rate
        if views_used:
            v_future_raw = future.loc[future["ds"] > cutoff, ["ds", "views"]].copy()
            v_future_raw = v_future_raw.rename(columns={"views": "views_raw"})

            future_fc = future_fc.merge(v_future_raw, on="ds", how="left")

            future_fc["expectedViews"] = future_fc["views_raw"].fillna(0.0).astype(float)

            # clip to at least 1 view/hour
            denom = future_fc["expectedViews"].where(future_fc["expectedViews"] > 0, 1.0)

            future_fc["expectedConversionRate"] = (
                (future_fc["expectedBookings"] / denom).clip(lower=0.0, upper=1.0)
            )

            # debug
            print("RAW future views describe:", v_future_raw["views_raw"].describe().to_dict())
            print("future_fc expectedViews describe:", future_fc["expectedViews"].describe().to_dict())

        else:
            future_fc["expectedViews"] = None
            future_fc["expectedConversionRate"] = None


        top = future_fc.sort_values("score", ascending=False).head(top_k)

        slots: List[Dict[str, Any]] = []
        for _, r in top.iterrows():
            dt_local_naive: datetime = r["ds"].to_pydatetime()
            dt_utc_out = _local_naive_to_utc(dt_local_naive)
            slots.append(
                {
                    "startAt": dt_utc_out,
                    "score": float(r["score"]),
                    "expectedBookings": float(r["expectedBookings"]),
                    "expectedRevenue": float(r["expectedRevenue"]),
                    "expectedViews": None if r["expectedViews"] is None else float(r["expectedViews"]),
                    "expectedConversionRate": None if r["expectedConversionRate"] is None else float(r["expectedConversionRate"]),
                }
            )

        # Categories: rank by realized revenue in window
        categories: List[Dict[str, Any]] = []
        if cat_revenue:
            top_cat = sorted(cat_revenue.items(), key=lambda x: x[1], reverse=True)[:5]
            maxv = top_cat[0][1] if top_cat else 1.0
            for cat, val in top_cat:
                categories.append({"category": cat, "score": float(val / maxv * 100.0), "realizedRevenue": float(val)})


        return OpportunityResult(
            slots=slots,
            algo_used="prophet_views" if views_used else "prophet",
            meta={
                "windowDays": window_days,
                "horizonDays": horizon_days,
                "points": int(len(df)),
                "avgPrice": avg_price,
                "viewsUsed": views_used,
            },
            categories=categories,
        )

    except Exception as e:
        # --- Heuristic fallback: hour-of-week historical mean ---
        df2 = df.copy()
        df2["weekday"] = df2["ds"].dt.weekday  # Mon=0
        df2["hour"] = df2["ds"].dt.hour

        grp = df2.groupby(["weekday", "hour"])["y"].mean().reset_index()
        maxy = grp["y"].max() if grp["y"].max() > 0 else 1.0
        grp["score_raw"] = (grp["y"] / maxy) * 100.0

        top = grp.sort_values("score_raw", ascending=False).head(top_k)

        slots: List[Dict[str, Any]] = []
        # Map each (weekday,hour) to its next occurrence in LOCAL time, then store UTC
        now_local = datetime.now(tz=TZ_LOCAL).replace(minute=0, second=0, microsecond=0)
        for _, r in top.iterrows():
            target_wd = int(r["weekday"])  # 0..6
            target_h = int(r["hour"])

            probe = now_local
            for _ in range(24 * 14):
                if probe.weekday() == target_wd and probe.hour == target_h and probe > now_local:
                    slots.append(
                        {
                            "startAt": probe.astimezone(TZ_UTC),
                            "score": float(r["score_raw"]),
                            "expectedBookings": float(r["y"]),
                            "expectedRevenue": float(r["y"] * avg_price),
                        }
                    )
                    break
                probe += timedelta(hours=1)

        return OpportunityResult(
            slots=slots,
            algo_used="heuristic",
            meta={"reason": "prophet_failed", "error": str(e)[:200], "viewsUsed": views_used},
            categories=[],
        )