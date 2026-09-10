# Supabase acceptance tests

These tests exercise the real Supabase APIs against the released `wodby/supabase-postgres:17-0.1.0` image in a dedicated local kind cluster. They cover Auth password login and existing sessions, REST row-level security, private Storage access, Realtime delivery, pause/resume, configuration upgrades, and coordinated database/object recovery with filesystem and S3 storage.

Requirements: Docker, kind, Helm, kubectl, Node.js 24 and Python 3.13 with `PyYAML==6.0.2` and `requests==2.32.5`. Allow enough free Docker disk space for Kubernetes, the component images and three small database volumes. S3 tests use an isolated MinIO fixture; no external bucket or credentials are needed.

```sh
helm dependency build stateful
state=$(mktemp -d)
kind create cluster --name supabase-acceptance --kubeconfig "$state/kubeconfig" --wait 120s
python3 scripts/supabase/acceptance.py \
  --kubeconfig "$state/kubeconfig" --state "$state/results" all
kind delete cluster --name supabase-acceptance
```

Use a new namespace for each complete run. The harness refuses non-local Kubernetes API addresses and refuses to install into an existing namespace. It does not alter the default kubeconfig. The state directory contains generated test credentials and must stay private; do not upload it or database/Secret dumps as CI artifacts. Delete the dedicated cluster after testing, including after failures.

Recovery stops application writers, creates a native database backup from a separate pod with read-only access to the database volume's encryption key, restores the archive into a fresh database volume with a different target password, restores the corresponding objects, then starts the APIs with the retained application tokens. It verifies old sessions, password login, RLS, Vault decryption, object bytes and Realtime after each restore. The S3 test copies into a separate bucket before switching to the recovered database.

The tests validate the image/chart contract. They do not exercise a platform deployment or its task orchestration. SMTP delivery, PostgreSQL major upgrades, and cross-bundle imports are outside this test suite.
