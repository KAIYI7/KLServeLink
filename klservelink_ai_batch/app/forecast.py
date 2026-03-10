from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Callable, Dict, Iterable, List, Optional

import logging

import pandas as pd
from zoneinfo import ZoneInfo

from app.arima_baseline import arima_forecast_hourly

TZ_LOCAL = ZoneInfo("Asia/Kuala_Lumpur")
TZ_UTC = ZoneInfo("UTC")

logger = logging.getLogger(__name__)


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


def _floor_hour(dt: datetime) -> datetime:
    return dt.replace(minute=0, second=0, microsecond=0)


def _utc_to_local_naive(dt_utc: datetime) -> datetime:
    dt_local = dt_utc.astimezone(TZ_LOCAL)
    return dt_local.replace(tzinfo=None)


def _local_naive_to_utc(dt_local_naive: datetime) -> datetime:
    dt_local = dt_local_naive.replace(tzinfo=TZ_LOCAL)
    return dt_local.astimezone(TZ_UTC)


def _as_float(v: Any) -> Optional[float]:
    if isinstance(v, (int, float)):
        return float(v)
    if isinstance(v, str):
        try:
            return float(v)
        except Exception:
            return None
    return None


def _status_for_demand(d: Dict[str, Any]) -> bool:
    """
    Conservative safety filter:
    keep normal lifecycle bookings, drop clear non-demand / failed outcomes.
    """
    status = str(d.get("status", "")).strip().lower()
    if status in {"cancelled", "canceled", "declined", "rejected", "failed"}:
        return False
    return True


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
        if dt_utc is None or dt_utc < start_utc or dt_utc >= end_utc:
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


def _build_hourly_booking_counts_local_naive(
        *,
        bookings: Iterable[Any],
        provider_id: Optional[str],
        start_utc: datetime,
        end_utc: datetime,
) -> pd.DataFrame:
    """
    Returns df: [ds (local naive hourly), y]
    Includes a full hourly grid with zeros, so hour-of-week averages are stable.
    """
    start_hr_utc = _floor_hour(start_utc)
    end_hr_utc = _floor_hour(end_utc)
    if end_hr_utc <= start_hr_utc:
        return pd.DataFrame(columns=["ds", "y"])

    start_local = _utc_to_local_naive(start_hr_utc)
    end_local_exclusive = _utc_to_local_naive(end_hr_utc)

    hours = pd.date_range(
        start=start_local,
        end=end_local_exclusive - timedelta(hours=1),
        freq="H",
    )
    df = pd.DataFrame({"ds": hours, "y": 0.0})

    if df.empty:
        return df

    pos = {ts.to_pydatetime(): i for i, ts in enumerate(hours)}

    for b in bookings:
        d = b.to_dict() if hasattr(b, "to_dict") else (b or {})

        if provider_id is not None and str(d.get("providerId") or "") != provider_id:
            continue

        if not _status_for_demand(d):
            continue

        dt_utc = _to_datetime(d.get("scheduledAt"))
        if dt_utc is None or dt_utc < start_utc or dt_utc >= end_utc:
            continue

        dt_local_hr = _utc_to_local_naive(_floor_hour(dt_utc))
        idx = pos.get(dt_local_hr)
        if idx is None:
            continue
        df.at[idx, "y"] += 1.0

    return df


def _hour_of_week_mean(series_df: pd.DataFrame, value_col: str) -> pd.Series:
    """
    series_df: columns ["ds", value_col] where ds is datetime
    Returns a MultiIndex-like series keyed by (weekday, hour) -> mean(value_col)
    """
    if series_df.empty:
        return pd.Series(dtype=float)

    tmp = series_df.copy()
    tmp["weekday"] = pd.to_datetime(tmp["ds"]).dt.weekday  # Mon=0
    tmp["hour"] = pd.to_datetime(tmp["ds"]).dt.hour
    return tmp.groupby(["weekday", "hour"])[value_col].mean()


def _fill_future_by_hour_of_week_mean(
        future: pd.DataFrame,
        mean_tbl: pd.Series,
        fallback: float,
) -> pd.Series:
    tmp = future.copy()
    tmp["weekday"] = pd.to_datetime(tmp["ds"]).dt.weekday
    tmp["hour"] = pd.to_datetime(tmp["ds"]).dt.hour
    idx = list(zip(tmp["weekday"].tolist(), tmp["hour"].tolist()))
    out = [float(mean_tbl.get(k, fallback)) for k in idx]
    return pd.Series(out, index=future.index, dtype=float)


def _iter_completed_prices(
        *,
        bookings: Iterable[Any],
        provider_id: Optional[str],
        start_utc: datetime,
        end_utc: datetime,
) -> List[float]:
    prices: List[float] = []
    for b in bookings:
        d = b.to_dict() if hasattr(b, "to_dict") else (b or {})

        if provider_id is not None and str(d.get("providerId") or "") != provider_id:
            continue

        dt_utc = _to_datetime(d.get("scheduledAt"))
        if dt_utc is None or dt_utc < start_utc or dt_utc >= end_utc:
            continue

        if str(d.get("status", "")).strip().lower() != "completed":
            continue

        for raw in (
                d.get("providerEarning"),
                d.get("providerPayout"),
                d.get("providerNet"),
                (d.get("payout") or {}).get("provider")
                if isinstance(d.get("payout"), dict)
                else None,
                (d.get("payment") or {}).get("providerAmount")
                if isinstance(d.get("payment"), dict)
                else None,
                d.get("totalAmount"),
                d.get("totalPrice"),
                d.get("amount"),
                d.get("price"),
                (d.get("pricing") or {}).get("total")
                if isinstance(d.get("pricing"), dict)
                else None,
                (d.get("pricing") or {}).get("amount")
                if isinstance(d.get("pricing"), dict)
                else None,
        ):
            v = _as_float(raw)
            if v is not None and v > 0:
                prices.append(v)
                break
    return prices


def _build_category_revenue(
        *,
        provider_bookings: Iterable[Any],
        provider_id: str,
        start_utc: datetime,
        end_utc: datetime,
        service_id_to_category: Optional[Dict[str, str]],
) -> List[Dict[str, Any]]:
    if not service_id_to_category:
        return []

    cat_revenue: Dict[str, float] = {}

    for b in provider_bookings:
        d = b.to_dict() if hasattr(b, "to_dict") else (b or {})
        if str(d.get("providerId") or "") != provider_id:
            continue

        dt_utc = _to_datetime(d.get("scheduledAt"))
        if dt_utc is None or dt_utc < start_utc or dt_utc >= end_utc:
            continue

        if str(d.get("status", "")).strip().lower() != "completed":
            continue

        sid = str(d.get("serviceId") or "")
        cat = str(service_id_to_category.get(sid, "")).strip()
        if not cat:
            continue

        amt = None
        for raw in (
                d.get("providerEarning"),
                d.get("providerPayout"),
                d.get("providerNet"),
                (d.get("payout") or {}).get("provider")
                if isinstance(d.get("payout"), dict)
                else None,
                (d.get("payment") or {}).get("providerAmount")
                if isinstance(d.get("payment"), dict)
                else None,
                d.get("totalAmount"),
                d.get("totalPrice"),
                d.get("amount"),
                d.get("price"),
        ):
            v = _as_float(raw)
            if v is not None and v > 0:
                amt = v
                break

        if amt is None:
            continue

        cat_revenue[cat] = cat_revenue.get(cat, 0.0) + amt

    if not cat_revenue:
        return []

    top_cat = sorted(cat_revenue.items(), key=lambda x: x[1], reverse=True)[:5]
    maxv = top_cat[0][1] if top_cat else 1.0
    if maxv <= 0:
        maxv = 1.0

    return [
        {
            "category": cat,
            "score": float(val / maxv * 100.0),
            "realizedRevenue": float(val),
        }
        for cat, val in top_cat
    ]


def provider_history_weight(n_bookings: int) -> float:
    if n_bookings < 5:
        return 0.15
    if n_bookings < 20:
        return 0.15 + (n_bookings - 5) * (0.65 / 15.0)
    return 0.80


def prophet_blend_weight(n_bookings: int) -> float:
    if n_bookings < 20:
        return 0.0
    if n_bookings < 50:
        return 0.60 + (n_bookings - 20) * (0.20 / 30.0)
    return 0.80


def _future_local_frame(*, now_utc: datetime, horizon_days: int) -> pd.DataFrame:
    next_hour_utc = _floor_hour(now_utc) + timedelta(hours=1)
    start_local = _utc_to_local_naive(next_hour_utc)
    periods = max(1, horizon_days * 24)
    future = pd.DataFrame(
        {
            "ds": pd.date_range(
                start=start_local,
                periods=periods,
                freq="H",
            )
        }
    )
    return future


def _build_hybrid_future_frame(
        *,
        future: pd.DataFrame,
        provider_hourly: pd.DataFrame,
        marketplace_hourly: pd.DataFrame,
        provider_booking_count: int,
        provider_avg_price: float,
        marketplace_avg_price: float,
) -> pd.DataFrame:
    out = future.copy()

    provider_pattern = _hour_of_week_mean(provider_hourly, "y")
    marketplace_pattern = _hour_of_week_mean(marketplace_hourly, "y")

    marketplace_global_mean = (
        float(marketplace_hourly["y"].mean()) if not marketplace_hourly.empty else 0.0
    )
    if marketplace_global_mean <= 0:
        marketplace_global_mean = 0.01

    w_provider = provider_history_weight(provider_booking_count)

    if provider_avg_price <= 0 and marketplace_avg_price <= 0:
        blended_avg_price = 0.0
    elif provider_avg_price <= 0:
        blended_avg_price = marketplace_avg_price
    elif marketplace_avg_price <= 0:
        blended_avg_price = provider_avg_price
    else:
        blended_avg_price = (
                w_provider * provider_avg_price
                + (1.0 - w_provider) * marketplace_avg_price
        )

    out["weekday"] = pd.to_datetime(out["ds"]).dt.weekday
    out["hour"] = pd.to_datetime(out["ds"]).dt.hour

    market_vals: List[float] = []
    provider_vals: List[float] = []
    lift_vals: List[float] = []
    shrunk_lift_vals: List[float] = []
    hybrid_vals: List[float] = []

    for wd, hr in zip(out["weekday"].tolist(), out["hour"].tolist()):
        hw = (int(wd), int(hr))

        marketplace_demand = float(marketplace_pattern.get(hw, marketplace_global_mean))
        if marketplace_demand <= 0:
            marketplace_demand = marketplace_global_mean

        # Provider signal:
        # because the provider hourly series is full-grid, this reflects actual historical
        # behavior by hour-of-week. Shrinkage avoids over-penalizing sparse providers.
        provider_pattern_val = float(provider_pattern.get(hw, 0.0))

        denom = max(marketplace_demand, 0.01)
        provider_lift = provider_pattern_val / denom

        shrunk_lift = 1.0 + w_provider * (provider_lift - 1.0)
        hybrid_expected_bookings = max(0.0, marketplace_demand * shrunk_lift)

        market_vals.append(marketplace_demand)
        provider_vals.append(provider_pattern_val)
        lift_vals.append(provider_lift)
        shrunk_lift_vals.append(shrunk_lift)
        hybrid_vals.append(hybrid_expected_bookings)

    out["marketplaceDemand"] = market_vals
    out["providerPattern"] = provider_vals
    out["providerLift"] = lift_vals
    out["shrunkLift"] = shrunk_lift_vals
    out["hybridExpectedBookings"] = hybrid_vals
    out["blendedAvgPrice"] = float(blended_avg_price)

    return out.drop(columns=["weekday", "hour"], errors="ignore")


def _fit_provider_prophet(
        *,
        provider_df: pd.DataFrame,
        provider_booking_count: int,
        horizon_days: int,
        views_df: pd.DataFrame,
        views_used: bool,
) -> tuple[Optional[pd.DataFrame], Dict[datetime, float], bool]:
    """
    Returns:
      (future_forecast_df, future_views_map, views_used_out)

    future_forecast_df columns:
      ds, yhat
    """
    if provider_booking_count < 20:
        return None, {}, False

    if len(provider_df) < 48:
        return None, {}, False

    if provider_df["y"].sum() <= 0 or provider_df["y"].nunique() < 2:
        return None, {}, False

    try:
        from prophet import Prophet
    except Exception:
        logger.warning("Prophet not available; skipping provider Prophet fit.")
        return None, {}, False

    try:
        m = Prophet(
            weekly_seasonality=True,
            daily_seasonality=True,
            seasonality_mode="additive",
        )

        if views_used:
            m.add_regressor("views", standardize=False)

        m.fit(provider_df)

        future = m.make_future_dataframe(
            periods=horizon_days * 24,
            freq="H",
            include_history=False,
        )

        future_views_map: Dict[datetime, float] = {}

        if views_used:
            try:
                mean_tbl = _hour_of_week_mean(views_df, "views")
                fallback = float(views_df["views"].mean()) if len(views_df) else 0.0
                future["views"] = _fill_future_by_hour_of_week_mean(
                    future, mean_tbl, fallback
                ).astype(float)

                for _, row in future.iterrows():
                    dt_local = pd.to_datetime(row["ds"]).to_pydatetime()
                    future_views_map[dt_local] = float(row["views"])
            except Exception as e:
                logger.warning("Prophet views regressor fallback failed: %s", e)
                future["views"] = 0.0
                future_views_map = {}
                views_used = False

        fc = m.predict(future)[["ds", "yhat"]].copy()
        fc["ds"] = pd.to_datetime(fc["ds"])
        fc["yhat"] = (
            pd.to_numeric(fc["yhat"], errors="coerce").fillna(0.0).clip(lower=0.0)
        )

        return fc, future_views_map, views_used
    except Exception as e:
        logger.exception("Prophet fit failed; falling back to hybrid baseline: %s", e)
        return None, {}, False


def _fit_provider_arima(
        *,
        provider_df: pd.DataFrame,
        horizon_days: int,
) -> Optional[pd.DataFrame]:
    if provider_df.empty or len(provider_df) < 48:
        return None

    if provider_df["y"].sum() <= 0 or provider_df["y"].nunique() < 2:
        return None

    try:
        fc = arima_forecast_hourly(
            provider_df[["ds", "y"]],
            horizon_hours=horizon_days * 24,
        )
        fc = fc[["ds", "yhat"]].copy()
        fc["ds"] = pd.to_datetime(fc["ds"])
        fc["yhat"] = (
            pd.to_numeric(fc["yhat"], errors="coerce").fillna(0.0).clip(lower=0.0)
        )
        return fc
    except Exception as e:
        logger.exception("ARIMA fit failed; falling back to hybrid baseline: %s", e)
        return None


def _finalize_slots(
        *,
        future_frame: pd.DataFrame,
        top_k: int,
) -> List[Dict[str, Any]]:
    if future_frame.empty:
        return []

    frame = future_frame.copy()

    frame["expectedBookings"] = (
        pd.to_numeric(frame["expectedBookings"], errors="coerce")
        .fillna(0.0)
        .clip(lower=0.0)
    )
    frame["expectedRevenue"] = (
        pd.to_numeric(frame["expectedRevenue"], errors="coerce").fillna(0.0)
    )

    # Rank by expected revenue, fall back to expected bookings when price is flat.
    rank_series = frame["expectedRevenue"]
    if float(rank_series.max()) <= 0:
        rank_series = frame["expectedBookings"]

    rank_max = float(rank_series.max()) if len(rank_series) else 0.0
    if rank_max > 0:
        frame["score"] = (rank_series / rank_max) * 100.0
    else:
        frame["score"] = 0.0

    frame = frame.sort_values(
        ["expectedRevenue", "expectedBookings", "ds"],
        ascending=[False, False, True],
    ).head(top_k)

    slots: List[Dict[str, Any]] = []
    for _, r in frame.iterrows():
        dt_local_naive: datetime = pd.to_datetime(r["ds"]).to_pydatetime()
        dt_utc_out = _local_naive_to_utc(dt_local_naive)

        expected_views = r.get("expectedViews")
        expected_conv = r.get("expectedConversionRate")

        slots.append(
            {
                "startAt": dt_utc_out,
                "score": float(r["score"]),
                "expectedBookings": float(r["expectedBookings"]),
                "expectedRevenue": float(r["expectedRevenue"]),
                "expectedViews": None
                if pd.isna(expected_views)
                else float(expected_views),
                "expectedConversionRate": None
                if pd.isna(expected_conv)
                else float(expected_conv),
            }
        )

    return slots


@dataclass
class OpportunityResult:
    slots: List[Dict[str, Any]]
    algo_used: str
    meta: Dict[str, Any]
    categories: List[Dict[str, Any]]


def build_opportunity_index(
        *,
        provider_id: str,
        provider_bookings: Iterable[Any],
        marketplace_bookings: Iterable[Any],
        horizon_days: int = 7,
        window_days: int = 28,
        min_points: int = 48,
        top_k: int = 12,
        service_id_to_category: Optional[Dict[str, str]] = None,
        view_events: Optional[Iterable[Any]] = None,
        use_views_regressor: bool = True,
        algo: str = "prophet",
        allowed_slot_fn: Optional[Callable[[datetime], bool]] = None,
) -> OpportunityResult:
    """
    Production hybrid forecaster.

    Core idea:
      marketplace_demand(hour_of_week)
      * provider_lift(hour_of_week, shrunk)
      * blended_avg_price

    When enough provider data exists, optionally blend with provider Prophet
    (or ARIMA when explicitly requested).

    Returns slots:
      [
        {
          startAt: UTC datetime,
          score: 0..100,
          expectedBookings: float,
          expectedRevenue: float,
          expectedViews: Optional[float],
          expectedConversionRate: Optional[float],
        },
        ...
      ]
    """
    now_utc = datetime.now(tz=TZ_UTC)
    start_utc = now_utc - timedelta(days=window_days)
    end_utc = now_utc

    algo_req = (algo or "prophet").lower().strip()

    provider_hourly = _build_hourly_booking_counts_local_naive(
        bookings=provider_bookings,
        provider_id=provider_id,
        start_utc=start_utc,
        end_utc=end_utc,
    )

    marketplace_hourly = _build_hourly_booking_counts_local_naive(
        bookings=marketplace_bookings,
        provider_id=None,
        start_utc=start_utc,
        end_utc=end_utc,
    )

    provider_booking_count = (
        int(provider_hourly["y"].sum()) if not provider_hourly.empty else 0
    )
    marketplace_booking_count = (
        int(marketplace_hourly["y"].sum()) if not marketplace_hourly.empty else 0
    )

    provider_prices = _iter_completed_prices(
        bookings=provider_bookings,
        provider_id=provider_id,
        start_utc=start_utc,
        end_utc=end_utc,
    )
    marketplace_prices = _iter_completed_prices(
        bookings=marketplace_bookings,
        provider_id=None,
        start_utc=start_utc,
        end_utc=end_utc,
    )

    provider_avg_price = (
        float(sum(provider_prices) / len(provider_prices)) if provider_prices else 0.0
    )
    marketplace_avg_price = (
        float(sum(marketplace_prices) / len(marketplace_prices))
        if marketplace_prices
        else 0.0
    )

    categories = _build_category_revenue(
        provider_bookings=provider_bookings,
        provider_id=provider_id,
        start_utc=start_utc,
        end_utc=end_utc,
        service_id_to_category=service_id_to_category,
    )

    future = _future_local_frame(now_utc=now_utc, horizon_days=horizon_days)
    future = _build_hybrid_future_frame(
        future=future,
        provider_hourly=provider_hourly,
        marketplace_hourly=marketplace_hourly,
        provider_booking_count=provider_booking_count,
        provider_avg_price=provider_avg_price,
        marketplace_avg_price=marketplace_avg_price,
    )

    # Working-hours / slot filter compatibility hook.
    if allowed_slot_fn is not None and not future.empty:
        keep_mask = []
        for ds in pd.to_datetime(future["ds"]).tolist():
            dt_local_naive = pd.to_datetime(ds).to_pydatetime()
            dt_utc = _local_naive_to_utc(dt_local_naive)
            try:
                keep_mask.append(bool(allowed_slot_fn(dt_utc)))
            except Exception:
                keep_mask.append(True)
        future = future.loc[keep_mask].reset_index(drop=True)

    # Start from the hybrid baseline so sparse providers still get output.
    blended_avg_price = float(future["blendedAvgPrice"].iloc[0]) if not future.empty else 0.0
    future["expectedBookings"] = future["hybridExpectedBookings"].astype(float)
    future["expectedRevenue"] = future["expectedBookings"] * blended_avg_price
    future["expectedViews"] = None
    future["expectedConversionRate"] = None

    algo_used = "hybrid"
    views_used = False
    w_provider = provider_history_weight(provider_booking_count)
    w_prophet = prophet_blend_weight(provider_booking_count)

    # Preserve provider-specific views regressor support for Prophet path.
    provider_df = provider_hourly[["ds", "y"]].copy()
    views_df = pd.DataFrame(columns=["ds", "views"])

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

            provider_df = provider_df.merge(v[["ds", "views"]], on="ds", how="left")
            provider_df["views"] = provider_df["views"].fillna(0.0).astype(float)

            if provider_df["views"].sum() > 0 and provider_df["views"].nunique() > 1:
                views_df = provider_df[["ds", "views"]].copy()
                views_used = True
            else:
                provider_df = provider_df.drop(columns=["views"], errors="ignore")
                views_used = False

    model_map: Dict[datetime, float] = {}
    future_views_map: Dict[datetime, float] = {}

    if algo_req in ("prophet", "auto", ""):
        prophet_fc, future_views_map, views_used_out = _fit_provider_prophet(
            provider_df=provider_df,
            provider_booking_count=provider_booking_count,
            horizon_days=horizon_days,
            views_df=views_df,
            views_used=views_used,
        )
        views_used = views_used_out

        if prophet_fc is not None and not prophet_fc.empty:
            model_map = {
                pd.to_datetime(r["ds"]).to_pydatetime(): float(r["yhat"])
                for _, r in prophet_fc.iterrows()
            }

            for i, row in future.iterrows():
                ds_local = pd.to_datetime(row["ds"]).to_pydatetime()
                hybrid_val = float(row["hybridExpectedBookings"])
                prophet_val = float(model_map.get(ds_local, hybrid_val))
                expected_bookings = (
                        w_prophet * max(0.0, prophet_val)
                        + (1.0 - w_prophet) * hybrid_val
                )

                future.at[i, "expectedBookings"] = expected_bookings
                future.at[i, "expectedRevenue"] = expected_bookings * blended_avg_price

                if views_used:
                    expected_views = float(future_views_map.get(ds_local, 0.0))
                    future.at[i, "expectedViews"] = expected_views
                    if expected_views > 0:
                        future.at[i, "expectedConversionRate"] = min(
                            1.0, max(0.0, expected_bookings / expected_views)
                        )
                    else:
                        future.at[i, "expectedConversionRate"] = None

            algo_used = "hybrid_prophet_views" if views_used else "hybrid_prophet"

    elif algo_req in ("arima", "sarimax"):
        arima_fc = _fit_provider_arima(
            provider_df=provider_hourly[["ds", "y"]].copy(),
            horizon_days=horizon_days,
        )
        if arima_fc is not None and not arima_fc.empty:
            w_model = w_prophet
            model_map = {
                pd.to_datetime(r["ds"]).to_pydatetime(): float(r["yhat"])
                for _, r in arima_fc.iterrows()
            }

            for i, row in future.iterrows():
                ds_local = pd.to_datetime(row["ds"]).to_pydatetime()
                hybrid_val = float(row["hybridExpectedBookings"])
                arima_val = float(model_map.get(ds_local, hybrid_val))
                expected_bookings = (
                        w_model * max(0.0, arima_val)
                        + (1.0 - w_model) * hybrid_val
                )

                future.at[i, "expectedBookings"] = expected_bookings
                future.at[i, "expectedRevenue"] = expected_bookings * blended_avg_price

            algo_used = "hybrid_arima"
        else:
            algo_used = "hybrid"

    else:
        # heuristic / unknown request -> stable hybrid fallback
        algo_used = "hybrid"

    slots = _finalize_slots(
        future_frame=future,
        top_k=top_k,
    )

    return OpportunityResult(
        slots=slots,
        algo_used=algo_used,
        meta={
            "windowDays": window_days,
            "horizonDays": horizon_days,
            "points": int(len(provider_hourly)),
            "providerBookings": int(provider_booking_count),
            "marketplaceBookings": int(marketplace_booking_count),
            "providerHistoryWeight": float(w_provider),
            "prophetBlendWeight": float(w_prophet),
            "providerAvgPrice": float(provider_avg_price),
            "marketplaceAvgPrice": float(marketplace_avg_price),
            "blendedAvgPrice": float(blended_avg_price),
            "viewsUsed": bool(views_used),
            "minPointsForModel": int(min_points),
        },
        categories=categories,
    )