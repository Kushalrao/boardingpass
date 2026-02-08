# Train Scraper API

FastAPI service for fetching Indian Railways train data. Designed to run on Google Cloud Run.

## Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/pnr/{pnr_number}` | GET | Get PNR status (10-digit PNR) |
| `/schedule/{train_number}` | GET | Get train schedule (5-digit train number) |
| `/live/{train_number}` | GET | Get live running status |
| `/search` | GET | Search trains between stations |

## Query Parameters

### `/live/{train_number}`
- `date` (optional): Date in YYYYMMDD format

### `/search`
- `from_station`: Source station code (e.g., NDLS)
- `to_station`: Destination station code (e.g., BCT)
- `date` (optional): Date in YYYYMMDD format

## Local Development

```bash
# Create virtual environment
python -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Run server
uvicorn main:app --reload --port 8080
```

## Docker Build

```bash
# Build image
docker build -t train-scraper .

# Run container
docker run -p 8080:8080 train-scraper
```

## Deploy to Cloud Run

```bash
# Build and push to GCR
gcloud builds submit --tag gcr.io/PROJECT_ID/train-scraper

# Deploy to Cloud Run
gcloud run deploy train-scraper \
  --image gcr.io/PROJECT_ID/train-scraper \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --memory 1Gi \
  --timeout 120
```

## Environment Variables

Set in Firebase Functions config:
- `TRAIN_SCRAPER_URL`: URL of deployed Cloud Run service
