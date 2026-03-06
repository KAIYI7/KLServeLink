from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Iterable, Optional, Tuple

import numpy as np
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
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=TZ_UTC)
    return dt.astimezone(TZ_UTC)


def _utc_to_local_naive(dt_utc: datetime) -> datetime:
    return dt_utc.astimezone(TZ_LOCAL).replace(tzinfo=None)


def build_hourly_counts(provider_id: str, bookings: Iterable[Any], window_days: int) -> pd.DataFrame:
    now_utc = datetime.now(tz=TZ_UTC)
    start_utc = now_utc - timedelta(days=window_days)

    rows = []
    for b in bookings:
        d = b.to_dict() if hasattr(b, "to_dict") else (b or {})
        if d.get("providerId") != provider_id:
            continue
        dt_utc = _to_datetime(d.get("scheduledAt"))
        if dt_utc is None or dt_utc < start_utc or dt_utc > now_utc:
            continue
        dt_hr = dt_utc.replace(minute=0, second=0, microsecond=0)
        rows.append(_utc_to_local_naive(dt_hr))

    ser = pd.Series(1, index=pd.to_datetime(rows)).resample("H").sum().fillna(0).astype(float)
    df = ser.reset_index()
    df.columns = ["ds", "y"]
    return df


def mae(y_true, y_pred) -> float:
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    return float(np.mean(np.abs(y_true - y_pred)))


def mape(y_true, y_pred) -> float:
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    denom = np.maximum(y_true, 1e-6)
    return float(np.mean(np.abs((y_true - y_pred) / denom)))


def eval_prophet(train_df: pd.DataFrame, test_periods: int) -> np.ndarray:
    from prophet import Prophet

    m = Prophet(weekly_seasonality=True, daily_seasonality=True)
    m.fit(train_df)

    future = m.make_future_dataframe(periods=test_periods, freq="H")
    fc = m.predict(future)
    yhat = fc["yhat"].clip(lower=0.0).to_numpy()
    return yhat[-test_periods:]


def eval_sarimax(train_y: np.ndarray, test_periods: int, seasonal_period: int = 168) -> np.ndarray:
    # SARIMA baseline
    from statsmodels.tsa.statespace.sarimax import SARIMAX  # :contentReference[oaicite:6]{index=6}

    model = SARIMAX(
        train_y,
        order=(1, 0, 1),
        seasonal_order=(1, 0, 1, seasonal_period),
        enforce_stationarity=False,
        enforce_invertibility=False,
    )
    res = model.fit(disp=False)
    fc = res.forecast(steps=test_periods)
    fc = np.clip(np.asarray(fc, dtype=float), 0.0, None)
    return fc


def benchmark(provider_id: str, bookings: Iterable[Any], window_days: int = 56, test_days: int = 7):
    df = build_hourly_counts(provider_id, bookings, window_days=window_days)
    if len(df) < (test_days * 24 + 7 * 24):
        raise RuntimeError("Not enough data for benchmark. Increase window_days or wait for more bookings.")

    test_periods = test_days * 24
    train_df = df.iloc[:-test_periods].copy()
    test_df = df.iloc[-test_periods:].copy()

    # Prophet
    pred_p = eval_prophet(train_df, test_periods=test_periods)

    # SARIMAX
    pred_a = eval_sarimax(train_df["y"].to_numpy(), test_periods=test_periods)

    y_true = test_df["y"].to_numpy()

    out = {
        "prophet_mae": mae(y_true, pred_p),
        "prophet_mape": mape(y_true, pred_p),
        "sarimax_mae": mae(y_true, pred_a),
        "sarimax_mape": mape(y_true, pred_a),
    }
    return out