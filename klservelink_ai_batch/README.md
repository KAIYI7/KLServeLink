# KLServeLink AI Batch Job (Cloud Run)

This folder deploys a **Cloud Run** service that runs your AI batch jobs **on-demand** (via HTTP) and can be scheduled using **Cloud Scheduler**.

## What it does
- **Module A (Recommendation):** writes `users/{uid}/recommendations.serviceIds` (Top 5 service IDs)
- **Module B (Forecasting):** writes `users/{providerId}/opportunity_index.slots` (Top future slots with score)
- **Module C (Review Analysis):** writes `services/{serviceId}.sentiment_score` and `services/{serviceId}.top_keywords`

## Firestore required fields
- `bookings`: `serviceId`, `providerId`, `scheduledAt` (Timestamp), `seekerId`, `totalAmount`
- `services`: `category`, `pricingRules`, `ratingAvg`, plus review subcollection `services/{serviceId}/reviews`

## API endpoints
- `POST /run/all`
- `POST /run/recommendations`
- `POST /run/forecast`
- `POST /run/reviews`

Each endpoint returns a small JSON summary.

## Authentication
- Deploy Cloud Run with **"Allow unauthenticated" OFF**
- Use an **OIDC authenticated** Cloud Scheduler job to call the endpoint.

The code uses `firebase-admin` and expects **Application Default Credentials** (ADC). On Cloud Run, ADC works automatically if the service account has Firestore access.

## Quick local test
1. `pip install -r requirements.txt`
2. Set `GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json`
3. `uvicorn app.main:app --reload --port 8080`
4. `curl -X POST http://localhost:8080/run/all`

