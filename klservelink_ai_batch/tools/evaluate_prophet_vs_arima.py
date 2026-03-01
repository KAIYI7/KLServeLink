from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple

import pandas as pd
from zoneinfo import ZoneInfo

import firebase_admin
from firebase_admin import credentials, firestore

from prophet import Prophet

from app.arima_baseline import arima_forecast_hourly


TZ_LOCAL = ZoneInfo("Asia/Kuala_Lumpur")
TZ_UTC = ZoneInfo("UTC")


def _to_datetime(ts) -> Optional[datetime]:
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
    return dt_utc.astimezone(TZ_LOCAL).replace(tzinfo=None)


def build_hourly_bookings_series(
        docs: List[Dict],
        provider_id: str,
        start_utc: datetime,
        end_utc: datetime,
        status_filter: Optional[List[str]] = None,
) -> pd.DataFrame:
    """
    Returns DataFrame with columns: ds (LOCAL naive hourly), y (bookings/hour)
    Covers the FULL window [start_utc, end_utc) at hourly resolution.
    """
    status_set = set(s.lower() for s in status_filter) if status_filter else None

    # Full hourly grid for the entire window (LOCAL naive)
    start_local = _utc_to_local_naive(_floor_hour(start_utc))
    end_local = _utc_to_local_naive(_floor_hour(end_utc))
    full_index = pd.date_range(start_local, end_local - pd.Timedelta(hours=1), freq="h")

    # Start with all zeros
    ser = pd.Series(0.0, index=full_index)

    rows: List[datetime] = []
    for d in docs:
        if str(d.get("providerId") or "") != provider_id:
            continue

        if status_set is not None:
            st = str(d.get("status") or "").lower().strip()
            if st not in status_set:
                continue

        dt_utc = _to_datetime(d.get("scheduledAt"))
        if dt_utc is None or dt_utc < start_utc or dt_utc >= end_utc:
            continue

        rows.append(_utc_to_local_naive(_floor_hour(dt_utc)))

    if rows:
        vc = pd.Series(rows).value_counts()
        # put counts into the full grid
        ser.loc[vc.index] = vc.values.astype(float)

    out = ser.reset_index()
    out.columns = ["ds", "y"]
    return out


def ensure_hourly_grid(df: pd.DataFrame) -> pd.DataFrame:
    """
    Ensures df has a continuous hourly grid with zeros for missing hours.
    """
    if df.empty:
        return df
    df = df.copy()
    df["ds"] = pd.to_datetime(df["ds"])
    df = df.sort_values("ds")

    full = pd.date_range(df["ds"].min(), df["ds"].max(), freq="h")
    df = df.set_index("ds").reindex(full).fillna(0.0).reset_index()
    df.columns = ["ds", "y"]
    return df


@dataclass
class Metrics:
    mae: float
    rmse: float
    smape: float
    wape: float


def compute_metrics(y_true: pd.Series, y_pred: pd.Series) -> Metrics:
    y_true = y_true.astype(float)
    y_pred = y_pred.astype(float)

    err = y_pred - y_true
    mae = float(err.abs().mean())
    rmse = float(math.sqrt((err * err).mean()))

    # sMAPE: 2|y - yhat| / (|y| + |yhat|) averaged
    denom = (y_true.abs() + y_pred.abs()).replace(0.0, 1e-9)
    smape = float((2.0 * err.abs() / denom).mean()) * 100.0

    # WAPE: sum|err| / sum|y|
    total_actual = float(y_true.abs().sum())
    wape = (float(err.abs().sum()) / total_actual * 100.0) if total_actual > 0 else 0.0

    return Metrics(mae=mae, rmse=rmse, smape=smape, wape=wape)


def fit_predict_prophet(train_df: pd.DataFrame, horizon_hours: int) -> pd.DataFrame:
    """
    Returns DataFrame columns: ds, yhat for next horizon_hours.
    """
    m = Prophet(
        weekly_seasonality=True,
        daily_seasonality=True,
        seasonality_mode="additive",
    )
    m.fit(train_df)

    cutoff = pd.to_datetime(train_df["ds"]).max()
    future = pd.DataFrame(
        {"ds": pd.date_range(cutoff + pd.Timedelta(hours=1), periods=horizon_hours, freq="h")}
    )
    fc = m.predict(future)
    out = fc[["ds", "yhat"]].copy()
    out["yhat"] = pd.to_numeric(out["yhat"], errors="coerce").fillna(0.0).clip(lower=0.0)
    return out


def fit_predict_arima(train_df: pd.DataFrame, horizon_hours: int) -> pd.DataFrame:
    """
    Returns DataFrame columns: ds, yhat for next horizon_hours.
    """
    out = arima_forecast_hourly(train_df[["ds", "y"]], horizon_hours=horizon_hours)
    out = out.copy()
    out["ds"] = pd.to_datetime(out["ds"])
    out["yhat"] = pd.to_numeric(out["yhat"], errors="coerce").fillna(0.0).clip(lower=0.0)
    return out


def fetch_bookings_firestore(
        db,
        provider_id: str,
        start_utc: datetime,
        end_utc: datetime,
) -> List[Dict]:
    q = (
        db.collection("bookings")
        .where("providerId", "==", provider_id)
        .where("scheduledAt", ">=", start_utc)
        .where("scheduledAt", "<", end_utc)
    )
    return [doc.to_dict() for doc in q.stream()]


def evaluate_once(
        docs: List[Dict],
        provider_id: str,
        train_start_utc: datetime,
        train_end_utc: datetime,
        test_end_utc: datetime,
        status_filter: Optional[List[str]] = None,
) -> Tuple[pd.DataFrame, Metrics, Metrics]:
    """
    One split:
      train: [train_start, train_end)
      test : [train_end, test_end)
    """
    train_df = build_hourly_bookings_series(
        docs, provider_id, train_start_utc, train_end_utc, status_filter=status_filter
    )
    test_df = build_hourly_bookings_series(
        docs, provider_id, train_end_utc, test_end_utc, status_filter=status_filter
    )

    train_df = ensure_hourly_grid(train_df)
    test_df = ensure_hourly_grid(test_df)

    horizon_hours = int((test_end_utc - train_end_utc).total_seconds() // 3600)
    if horizon_hours <= 0 or test_df.empty or train_df.empty:
        raise ValueError("Not enough data for this split.")

    fc_prophet = fit_predict_prophet(train_df, horizon_hours=horizon_hours)
    fc_arima = fit_predict_arima(train_df, horizon_hours=horizon_hours)

    fc_prophet = fc_prophet.rename(columns={"yhat": "yhat_prophet"})
    fc_arima = fc_arima.rename(columns={"yhat": "yhat_arima"})

    # Align
    test_df["ds"] = pd.to_datetime(test_df["ds"])
    merged = (
        test_df
        .merge(fc_prophet, on="ds", how="left")
        .merge(fc_arima, on="ds", how="left")
    )

    merged["yhat_prophet"] = merged["yhat_prophet"].fillna(0.0)
    merged["yhat_arima"] = merged["yhat_arima"].fillna(0.0)

    m_prophet = compute_metrics(merged["y"], merged["yhat_prophet"])
    m_arima = compute_metrics(merged["y"], merged["yhat_arima"])

    return merged, m_prophet, m_arima


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--providerId", required=True)
    ap.add_argument("--trainDays", type=int, default=28)
    ap.add_argument("--testDays", type=int, default=7)
    ap.add_argument("--folds", type=int, default=1, help="Rolling folds (1 = single holdout)")
    ap.add_argument("--foldStepDays", type=int, default=7, help="Shift window by this many days per fold")
    ap.add_argument("--status", default="", help="Comma list, e.g. completed,accepted (empty = all)")
    ap.add_argument("--outCsv", default="model_eval.csv")
    args = ap.parse_args()

    if not firebase_admin._apps:
        # Uses GOOGLE_APPLICATION_CREDENTIALS by default
        firebase_admin.initialize_app(credentials.ApplicationDefault())
    db = firestore.client()

    now_utc = datetime.now(tz=TZ_UTC).replace(minute=0, second=0, microsecond=0)

    status_filter = [s.strip() for s in args.status.split(",") if s.strip()] or None

    # Fetch enough history to cover all folds.
    total_span_days = args.trainDays + args.testDays + (args.folds - 1) * args.foldStepDays
    start_utc = now_utc - timedelta(days=total_span_days + 2)  # +2 days buffer
    end_utc = now_utc + timedelta(days=1)

    docs = fetch_bookings_firestore(db, args.providerId, start_utc, end_utc)

    rows = []
    for fold in range(args.folds):
        # rolling origin: last fold tests closest to now
        test_end = now_utc - timedelta(days=fold * args.foldStepDays)
        train_end = test_end - timedelta(days=args.testDays)
        train_start = train_end - timedelta(days=args.trainDays)

        merged, mp, ma = evaluate_once(
            docs,
            args.providerId,
            train_start,
            train_end,
            test_end,
            status_filter=status_filter,
        )

        rows.append(
            {
                "fold": fold,
                "train_start_utc": train_start.isoformat(),
                "train_end_utc": train_end.isoformat(),
                "test_end_utc": test_end.isoformat(),
                "prophet_mae": mp.mae,
                "prophet_rmse": mp.rmse,
                "prophet_smape_%": mp.smape,
                "prophet_wape_%": mp.wape,
                "arima_mae": ma.mae,
                "arima_rmse": ma.rmse,
                "arima_smape_%": ma.smape,
                "arima_wape_%": ma.wape,
                "test_points": int(len(merged)),
            }
        )

    out = pd.DataFrame(rows).sort_values("fold")
    out.to_csv(args.outCsv, index=False)

    print("\n=== Results (lower is better) ===")
    print(out.to_string(index=False))
    print(f"\nSaved: {args.outCsv}")


if __name__ == "__main__":
    main()