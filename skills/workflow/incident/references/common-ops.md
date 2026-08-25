# Common Operations Reference

Load this when the incident involves infrastructure you can SSH into or when the engineer needs copy-paste commands.

---

## Database Failover

### Managed HA (RDS / Cloud SQL / Patroni)

```bash
# AWS RDS — force failover to standby
aws rds failover-db-cluster --db-cluster-identifier production-auth-cluster

# Patroni — trigger failover
patronictl failover production-cluster
```

### Manual Promotion (warm standby / replica)

```bash
# PostgreSQL — promote standby to primary
pg_ctl promote -D /var/lib/postgresql/data

# MySQL — stop replication, make writable
mysql -e "STOP SLAVE; RESET SLAVE ALL;"
# Then update app config DB_HOST to point to new primary
kubectl rollout restart deployment/<app>
kubectl rollout status deployment/<app> --timeout=120s
```

### Verify Recovery

```bash
# Quick connectivity check
psql -h <db-host> -U <user> -d <db> -c "SELECT 1;"

# Check replication lag (on standby)
SELECT extract(epoch from (now() - pg_last_xact_replay_timestamp())) AS lag_seconds;
```

---

## Connection Refused Quick Fixes

| Symptom | Quick Test | Fix |
|---|---|---|
| Max connections | `SELECT count(*) FROM pg_stat_activity;` | Terminate idle backends or bump `max_connections` |
| Disk full | `df -h` | Purge old logs / WAL; extend volume |
| Listen address wrong | `ss -tlnp \| grep :5432` | Fix `listen_addresses` in postgresql.conf |
| Firewall / SG change | Check terraform / cloud console | Restore previous security group rules |
| Certificate expiry | Check TLS handshake logs | Renew or disable TLS temporarily |

---

## Investigation Queries

```sql
-- Active connections and their queries
SELECT pid, usename, application_name, client_addr, state, wait_event_type, wait_event, query_start, state_change
FROM pg_stat_activity
WHERE backend_type = 'client backend';

-- Blocking locks
SELECT * FROM pg_locks WHERE NOT granted;

-- Long-running transactions
SELECT pid, usename, query, now() - query_start AS duration
FROM pg_stat_activity
WHERE now() - query_start > interval '5 minutes';
```

---

## Circuit Breaker / Kill-Switch Operations

### Feature Flag Kill-Switch

```bash
# LaunchDarkly example — disable a feature
ldcli flags update --project <project> --flag <flag-key> --environments <env> --patch '{"op": "replace", "path": "/environments/<env>/on", "value": false}'

# Generic — flip config flag and restart
kubectl set env deployment/<app> FEATURE_X_ENABLED=false
kubectl rollout restart deployment/<app>
```

### Circuit Breaker Config (example: Hystrix / Resilience4j)

```bash
# Verify circuit state
kubectl exec <pod> -- curl -s localhost:8080/actuator/circuitbreakers

# Open circuit manually if downstream is failing
# (implementation-specific — update config map or property)
```

---

## Alert Tuning (S4 / Noise)

When an alert fires but there is no actual impact:

1. **Verify sustained signal** — one spike ≠ incident.
2. **Check correlation** — CPU 85% with flat error rate = noise.
3. **Raise threshold** — e.g., CPU alert from 80% → 90% or require 2 consecutive datapoints.
4. **Add dimension** — alert on `cpu AND error_rate` instead of CPU alone.
5. **Add seasonality** — ignore expected batch-job spikes (e.g., Friday evening digest runs).
6. **Close and document** — note tuning change in incident tracker for review.

---

## Evidence Preservation Commands

Before any mitigation:

```bash
# Capture current DB state
ssh <db-host> "psql -c \"COPY (SELECT * FROM pg_stat_activity) TO '/tmp/pg_stat_activity_\$(date +%s).csv' WITH CSV;\""

# Capture logs
ssh <db-host> "sudo tail -n 500 /var/log/postgresql/postgresql-*.log > /tmp/pg_logs_\$(date +%s).log"

# System state
ssh <db-host> "vmstat 1 10 > /tmp/vmstat_\$(date +%s).log"
ssh <db-host> "iostat -x 1 10 > /tmp/iostat_\$(date +%s).log"
```
