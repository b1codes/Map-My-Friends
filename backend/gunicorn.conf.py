"""gunicorn's settings for the production image (it reads this from /app).

The shape Cloud Run recommends for an instance with one vCPU: one worker
process, with threads for concurrency, since most of a request is spent waiting
on Firestore. The load test (`make load`) runs this same image and measured it.
"""

import os

# Cloud Run tells the container which port to listen on.
bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"
workers = int(os.environ.get("GUNICORN_WORKERS", "1"))
threads = int(os.environ.get("GUNICORN_THREADS", "8"))
worker_class = "gthread"
# Cloud Run enforces the request timeout itself, so gunicorn mustn't kill a
# worker under it first.
timeout = 0
# Cloud Run sends SIGTERM and allows 10 s before SIGKILL.
graceful_timeout = 8
# Access log to stdout, which Cloud Logging collects (and scripts/load.sh and
# scripts/dast.sh count).
accesslog = "-"
