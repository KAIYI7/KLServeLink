# KLServeLink Seed Tools (Medium Demo)

This folder contains:
- `seed_firestore.py` : seeds Firestore with synthetic users, bookings, and reviews (tagged with `seedTag`)
- `delete_seed.py`   : deletes everything created by a given `seedTag`

## 0) Prereqs
1. Install Python 3.10+.
2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

## 1) Auth (pick ONE)

### Option A (recommended): gcloud Application Default Credentials
```bash
gcloud auth application-default login
gcloud config set project klservelink
```

### Option B: Service account key
Download a service account JSON key and set:
```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/key.json"
```

## 2) Seed (Medium demo)
```bash
python seed_firestore.py --project klservelink \
  --provider-id <REAL_PROVIDER_UID> \
  --real-seeker-id <REAL_SEEKER_UID> \
  --primary-service-id <PRIMARY_SERVICE_ID> \
  --bookings 300 --reviews 80
```

The script will print a `seedTag` like:
`seed_medium_20260207_154210`

It also writes a manifest:
`seed_runs/<seedTag>`

## 3) Delete
```bash
python delete_seed.py --project klservelink --seed-tag <seedTag>
```

## Safety
- Everything seeded has `isSynthetic=true` and `seedTag=<seedTag>`.
- Delete uses the manifest so it won't touch your real data.


## 4) Seed services with more realistic titles (optional but recommended for demos)

This creates active services with more natural names/descriptions + required fields (`type`, `photoUrls`, etc.).
Run this first if your current `services` collection looks too synthetic.

```bash
python seed_services.py --project klservelink   --focus-provider-id <REAL_PROVIDER_UID>   --total-services 50 --focus-provider-services 10
```

It will print a `seedTag` and a suggested `--primary-service-id` for `seed_firestore.py`.

## Notes on booking schema

`seed_firestore.py` writes a `payment` map (new schema) and keeps `paymentMethod` for backward compatibility.
