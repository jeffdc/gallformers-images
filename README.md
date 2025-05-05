# Gallformers Image Service

A standalone Go micro‑service that **accepts image uploads, streams the originals straight to S3, then performs all post‑processing** (EXIF strip, responsive resizing, thumbnail) before writing the derivatives back to S3.  It completely removes heavy image handling from the Node web tier.

---

## Features

* **Direct upload endpoint** – clients `POST` multipart images to `/v1/images`; the service streams to S3 without buffering the full file in RAM.
* **EXIF strip → libvips** – privacy‑safe, minimal file size.
* **Multi‑size derivatives** – 2048 px, 1024 px, 512 px, 200 px square thumbnail.
* **Asynchronous processing** – upload returns `202 Accepted` + `jobId`; progress is polled via `GET /v1/jobs/{id}`.
* **Transparent queue & back‑pressure** – bounded in‑memory queue, global semaphore; service replies `202` immediately even when under load.
* **Low memory** – runs in 256 MB Fly VM with steady‑state RSS < 120 MB.
* **Batch re‑processing tool** – same container, alternate entrypoint.
* **Open Source** – Apache 2.0; dynamically links LGPL 2.1 libvips.

---

## Tech Stack

| Layer | Choice |
|-------|--------|
| Language | Go 1.22 |
| Image lib | libvips via `bimg` |
| HTTP | `go-chi/chi` |
| Streaming upload | `github.com/aws/aws-sdk-go-v2/feature/s3/manager` MultipartUploader |
| Metrics | `prometheus/client_golang` |
| Container | Alpine multi‑stage, non‑root |
| Platform | Fly.io (shared‑cpu‑1x, 256 MB) |

---

## API (v1)

| Method & Path | Purpose | Request | Response |
|---------------|---------|---------|----------|
| `POST /v1/images` | Upload original & enqueue processing | `multipart/form-data` field `file` (max 30 MB) | `202 Accepted` `{ "jobId": "…" }` |
| `GET /v1/jobs/{id}` | Poll status | — | `{ status: processing|done|error, derivatives:[…] }` |
| `GET /healthz` | Fly healthcheck | — | `200 OK` |
| `GET /metrics` | Prometheus | — | Prom metrics |

When the job is **done**, the response payload lists the S3 keys of each derivative so the UI can reference them.

---

## Directory structure

```
.
├── cmd/
│   ├── service/      # HTTP upload + queue
│   └── reprocess/    # batch tool entry‑point
├── internal/
│   ├── api/          # handlers, DTOs, validation
│   ├── pipeline/     # image pipeline (bimg wrappers)
│   ├── queue/        # bounded queue + metrics
│   └── storage/      # S3 adapter (stream upload, get object)
├── pkg/
│   └── config/       # env parsing & validation
├── Dockerfile
├── fly.toml
├── Makefile
├── PLAN.md           # task tracker
├── LICENSE           # Apache‑2.0
└── NOTICE            # third‑party licences (libvips LGPL 2.1)
```

---

## Quick start (local)

Prereqs: Go 1.22, Docker, AWS creds with write‑only access to bucket.

```bash
# build and test
make test

# run service locally (reads .env)
go run ./cmd/service

# upload an image and start processing
curl -F "file=@/path/to/photo.jpg" http://localhost:8080/v1/images
# → {"jobId":"123e4567…"}

# poll for completion
curl http://localhost:8080/v1/jobs/123e4567
```

Derivatives will appear under `s3://$S3_BUCKET/full/…`, `medium/…`, `small/…`, `thumb/…`.

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `AWS_ACCESS_KEY_ID` | — | S3 write‑only creds |
| `AWS_SECRET_ACCESS_KEY` | — | – |
| `AWS_REGION` | `us‑east‑1` | — |
| `S3_BUCKET` | — | Bucket for originals & derivatives |
| `MAX_UPLOAD_MB` | `30` | Hard upload size limit |
| `QUEUE_SIZE` | `64` | Max enqueued jobs |
| `WORKERS` | `2` | Concurrent workers |
| `LOG_LEVEL` | `info` | `debug`,`info`,`warn`,`error` |
| `PORT` | `8080` | HTTP listen port |

---

## Building the container

```bash
DOCKER_BUILDKIT=1 docker build -t gf-img:latest .
```

---

## Deploying to Fly.io

```bash
fly launch --name gf-img --no-deploy
fly secrets set AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=… S3_BUCKET=… AWS_REGION=us-east-1
fly deploy --vm-size shared-cpu-1x --memory 256
```

Health check endpoint: `/healthz`.

---

## Batch re‑processing

```bash
fly scale memory 512         # temporary
fly ssh console --command "/app/reprocess -workers=2 -prefix originals/"
fly scale memory 256         # reset
```

---

## Observability

Prometheus metrics at `/metrics`:

* `jobs_total{status}`
* `queue_depth`
* `job_duration_seconds` (histogram)
* `upload_bytes_total`

Alert example (Grafana Cloud):

```yaml
aexpr: queue_depth > (WORKERS * 4)
for: 5m
labels:
  severity: warning
```

---

## Licence & notices

* **Gallformers Image Service** – © 2025 Jeff Clark, Apache 2.0
* **libvips** – LGPL 2.1, dynamically linked; see `NOTICE`.

---

## Contributing

PRs welcome.  Run `make lint test` before submission.

