# Gallformers Image Service – Implementation Plan

> **Goal**  Replace the in‑process Node image handling with a standalone, low‑memory Go service on Fly.io that performs EXIF stripping, multi‑size resizing, thumbnail creation and S3 upload with transparent queuing and batch re‑processing support.

---

## Task Breakdown

| ID | Task | Description | Acceptance Criteria |
|----|------|-------------|---------------------|
| 1 | Repository bootstrap | Initialise Go module, CI (GitHub Actions), Dependabot. | `go test ./...` passes in CI. |
| 2 | Pipeline library | Implement `internal/pipeline` using **bimg/libvips** with unit‑tests for EXIF strip + four resize outputs. | Tests complete < 250 ms, RSS < 50 MB. |
| 3 | Queue + workers | Channel‑backed bounded queue, global semaphore; Prometheus metrics `jobs_total`, `queue_depth`. | Load‑test 30 concurrent jobs on 256 MB VM without OOM. |
| 4 | HTTP API | `POST /v1/jobs` (202 Accepted) and `GET /v1/jobs/{id}` using go‑chi; input validation. | OpenAPI spec generated; integration test green. |
| 5 | S3 adapter | Write‑only AWS SDK v2 client; uploads public‑read to single bucket. | Unit‑test via MinIO in CI. |
| 6 | Dockerfile | Multi‑stage Alpine build; runtime image ≤ 40 MB; non‑root user. | `docker run` processes sample images successfully. |
| 7 | Fly deploy | `fly launch`, secrets, memory 256 MB, shared‑cpu‑1x; healthcheck endpoint. | `fly status` shows healthy deployment. |
| 8 | Batch reprocess tool | `cmd/reprocess` streams 20 k originals and re‑uses pipeline with `workers=2`. | Completes 20 k sample run in ≤ 24 h on 512 MB VM. |
| 9 | Observability | Prometheus metrics + JSON structured logs; alert on `queue_depth > workers*4` for 5 min. | Metrics visible in Fly dashboard; manual alert test triggers. |
| 10 | Cut‑over & cleanup | Shadow‑write from Node backend, diff outputs for 1 week, then switch primary. | Error rate < 0.5 % post‑cut‑over; old code removed. |

---

## Milestones & Timeline (suggested)

| Milestone | Tasks | Target |
|-----------|-------|--------|
| **M1 – Pipeline & API** | 1‑4 | +5 days |
| **M2 – Container & Fly** | 5‑7 | +3 days |
| **M3 – Batch Tool** | 8 | +2 days |
| **M4 – Observability & Cut‑over** | 9‑10 | +2 days |

---

## Definition of Done

* All acceptance criteria met and CI green.
* README updated with any deviations.
* Fly deployment automated via `fly deploy` in CI.
* NOTICE file includes LGPL 2.1 text for libvips.
* New image processing service called from main site via feature flag for production testing
* Old in‑process image code deleted from main website.

---

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `AWS_ACCESS_KEY_ID` | S3 write‑only access |
| `AWS_SECRET_ACCESS_KEY` | –  |
| `AWS_REGION` | e.g. `us‑east‑1` |
| `S3_BUCKET` | Public read bucket for derivatives |
| `QUEUE_SIZE` | Bounded queue length (default 64) |
| `WORKERS` | Concurrent workers (default 2) |

---

## References
* [libvips licence](https://github.com/libvips/libvips/blob/master/COPYING) – ship in `NOTICE`.
* Fly.io Prometheus docs: <https://fly.io/docs/reference/metrics/>

