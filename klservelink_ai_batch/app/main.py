from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel
from app import jobs
from app.jobs import run_recommendations, run_reviews

app = FastAPI(title="KLServeLink AI Batch Jobs")

class RunResponse(BaseModel):
    ok: bool
    detail: str
    stats: dict = {}

@app.get("/health")
def health():
    return {"ok": True}

@app.post("/run/recommendations", response_model=RunResponse)
def run_rec():
    stats = run_recommendations()
    return RunResponse(ok=True, detail="recommendations updated", stats=stats)

@app.post("/run/forecast", response_model=RunResponse)
def run_fc(
        algo: str = Query("prophet", pattern="^(prophet|arima|sarimax|auto)$"),
):
    stats = jobs.run_forecast(algo=algo)
    return RunResponse(ok=True, detail="opportunity_index updated", stats=stats)

@app.post("/run/reviews", response_model=RunResponse)
def run_rv():
    stats = run_reviews()
    return RunResponse(ok=True, detail="sentiment + keywords updated", stats=stats)

@app.post("/run/all", response_model=RunResponse)
def run_all():
    a = run_recommendations()
    b = jobs.run_forecast(algo="prophet")
    c = run_reviews()
    return RunResponse(ok=True, detail="all jobs completed", stats={"recommendations": a, "forecast": b, "reviews": c})
