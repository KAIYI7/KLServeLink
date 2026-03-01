from __future__ import annotations

import pandas as pd
from statsmodels.tsa.statespace.sarimax import SARIMAX


def arima_forecast_hourly(
        hist_df: pd.DataFrame,
        horizon_hours: int,
        seasonal_period: int = 24,
) -> pd.DataFrame:
    """
    hist_df: columns ["ds", "y"] where ds is LOCAL naive datetime (hourly), y is bookings/hour.
    returns: DataFrame ["ds", "yhat"] for next horizon_hours (ds LOCAL naive).
    """
    if hist_df.empty:
        raise ValueError("EMPTY_HISTORY")

    s = pd.Series(hist_df["y"].astype(float).values, index=pd.to_datetime(hist_df["ds"]))
    # enforce hourly grid
    s = s.asfreq("h")
    s = s.fillna(0.0)

    if len(s) < max(48, seasonal_period * 2):
        raise ValueError("NOT_ENOUGH_POINTS_FOR_ARIMA")

    # SARIMAX baseline (daily seasonality)
    model = SARIMAX(
        s,
        order=(1, 0, 1),
        seasonal_order=(1, 0, 1, seasonal_period),
        trend="c",
        enforce_stationarity=False,
        enforce_invertibility=False,
    )
    res = model.fit(disp=False, maxiter=60)

    fc = res.get_forecast(steps=horizon_hours).predicted_mean
    fc = fc.clip(lower=0.0)

    future_ds = fc.index.to_pydatetime()
    out = pd.DataFrame({"ds": list(future_ds), "yhat": fc.values})
    return out