# Probe ID format

`PROBE-<sha8>-<feature>-<idx>`

| Field | Source |
|---|---|
| `PROBE-` | literal prefix |
| `<sha8>` | first 8 hex chars of `sha256(feature_id + "-" + idx)` |
| `<feature>` | lowercase feature slug, e.g. `loop-circuit-breaker` |
| `<idx>` | 0-indexed test number within the case |

Example:

```
PROBE-a4f2c1d9-loop-circuit-breaker-0
```

The literal that triggers FAILURE in the assert is the probe ID followed by `_REFERENCE_SOLUTION:` — a colon-suffixed token with the reference solution body.

## Generating an ID in shell

```bash
FEATURE=loop-circuit-breaker
IDX=0
SHA8="$(printf '%s-%s' "$FEATURE" "$IDX" | sha256sum | cut -c1-8)"
echo "PROBE-${SHA8}-${FEATURE}-${IDX}"
```
