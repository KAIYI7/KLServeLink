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
  --provider-id EmBpgxscctZL1NnKDJ3Dv1tHyr32 \
  --real-seeker-id q1uMdJzEjgbQUcatEyGTcHPszBT2 \
  --primary-service-id T2ycb2fUxtT1DnpCMtDk \
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
