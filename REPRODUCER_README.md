# WAF ConfigMap Dynamic Reload Reproducer

Attempts to reproduce [solo-projects#8773](https://github.com/solo-io/solo-projects/issues/8773): updates to a `ConfigMap` referenced by `configMapRuleSets` in a `VirtualHostOption` are not dynamically reloaded in gloo-proxy pods.

## Resources

### ConfigMaps (shared between simple and complex scenarios)

| File | ConfigMap name | Rules loaded |
|---|---|---|
| `waf-rules-configmap-1.yaml` | `waf-rules` | rule 1001: blocks `X-Bad-Header: blocked` |
| `waf-rules-configmap-2.yaml` | `waf-rules` | rule 1001 + rule 1002: also blocks `X-Block-Me: true` |

Both files share the same Kubernetes object name (`waf-rules`) so they can be swapped in place with `kubectl apply`.

### WAF policies

| File | Type | Config |
|---|---|---|
| `waf-virtualhostoption.yaml` | `VirtualHostOption` | `configMapRuleSets` only |
| `waf-virtualhostoption-complex.yaml` | `VirtualHostOption` | `configMapRuleSets` + inline `ruleSets` (rule 3001: blocks `X-Inline-Block: true`) |
| `waf-virtualhostoption-crs.yaml` | `VirtualHostOption` | `configMapRuleSets` + `coreRuleSet` (OWASP CRS, paranoia level 1, anomaly threshold 100) + inline `ruleSets` (rule 3001) |

### Scripts (run from the `install/` directory)

| Script | Action |
|---|---|
| `setup-waf-simple.sh` | Apply config-1 + simple VHO |
| `setup-waf-complex.sh` | Apply config-1 + complex VHO |
| `setup-waf-crs.sh` | Apply config-1 + CRS VHO |
| `configure-waf-1.sh` | Switch to config-1 (1 rule) |
| `configure-waf-2.sh` | Switch to config-2 (2 rules) |
| `remove-waf-simple.sh` | Delete ConfigMaps + simple VHO |
| `remove-waf-complex.sh` | Delete ConfigMaps + complex VHO |
| `remove-waf-crs.sh` | Delete ConfigMaps + CRS VHO |

## Steps to Reproduce

Both scenarios use the K8s Gateway API proxy on port 80.

### Simple scenario (`configMapRuleSets` only)

**1. Set up**

```sh
cd install && ./setup-waf-simple.sh
```

**2. Verify config-1 is active**

```sh
curl -v -H "X-Bad-Header: blocked" http://api.example.com/get  # 403 — blocked by rule 1001
curl -v -H "X-Block-Me: true"      http://api.example.com/get  # 200 — rule 1002 not yet loaded
```

**3. Switch to config-2**

```sh
./configure-waf-2.sh
```

**4. Verify config-2 is active**

```sh
curl -v -H "X-Bad-Header: blocked" http://api.example.com/get  # 403 — blocked by rule 1001
curl -v -H "X-Block-Me: true"      http://api.example.com/get  # 403 if reloaded; 200 if bug present
```

**5. Clean up**

```sh
./remove-waf-simple.sh
```

---

### Complex scenario (`configMapRuleSets` + inline `ruleSets`)

**1. Set up**

```sh
cd install && ./setup-waf-complex.sh
```

**2. Verify config-1 is active**

```sh
curl -v -H "X-Bad-Header: blocked"  http://api.example.com/get  # 403 — blocked by rule 1001
curl -v -H "X-Block-Me: true"       http://api.example.com/get  # 200 — rule 1002 not yet loaded
curl -v -H "X-Inline-Block: true"   http://api.example.com/get  # 403 — blocked by inline rule 3001
```

**3. Switch to config-2**

```sh
./configure-waf-2.sh
```

**4. Verify config-2 is active**

```sh
curl -v -H "X-Bad-Header: blocked"  http://api.example.com/get  # 403 — blocked by rule 1001
curl -v -H "X-Block-Me: true"       http://api.example.com/get  # 403 if reloaded; 200 if bug present
curl -v -H "X-Inline-Block: true"   http://api.example.com/get  # 403 — inline rule always active
```

**5. Clean up**

```sh
./remove-waf-complex.sh
```

---

### CRS scenario (`configMapRuleSets` + `coreRuleSet` + inline `ruleSets`)

The OWASP CRS is loaded with paranoia level 1 and a high anomaly threshold (100) so that normal requests are not blocked by CRS rules. The configmap and inline rules continue to use explicit `deny` actions and are unaffected by the anomaly threshold.

**1. Set up**

```sh
cd install && ./setup-waf-crs.sh
```

**2. Verify config-1 is active**

```sh
curl -v -H "X-Bad-Header: blocked" http://api.example.com/get  # 403 — blocked by rule 1001
curl -v -H "X-Block-Me: true"      http://api.example.com/get  # 200 — rule 1002 not yet loaded
curl -v -H "X-Inline-Block: true"  http://api.example.com/get  # 403 — blocked by inline rule 3001
curl -v                            http://api.example.com/get  # 200 — CRS does not block normal requests
```

**3. Switch to config-2**

```sh
./configure-waf-2.sh
```

**4. Verify config-2 is active**

```sh
curl -v -H "X-Bad-Header: blocked" http://api.example.com/get  # 403 — blocked by rule 1001
curl -v -H "X-Block-Me: true"      http://api.example.com/get  # 403 if reloaded; 200 if bug present
curl -v -H "X-Inline-Block: true"  http://api.example.com/get  # 403 — inline rule always active
curl -v                            http://api.example.com/get  # 200 — CRS does not block normal requests
```

**5. Clean up**

```sh
./remove-waf-crs.sh
```

---

## Findings

**Gloo Gateway 1.20.6 — bug NOT reproduced in either configuration.**

### Simple configuration (`configMapRuleSets` only)

Switching from config-1 to config-2 via `kubectl apply` was reflected immediately in gloo-proxy. The `X-Block-Me: true` rule became active without a delete/recreate cycle.

### Complex configuration (`configMapRuleSets` + inline `ruleSets`)

Same result. Dynamic reload worked correctly when `configMapRuleSets` was combined with an inline `ruleSets` entry.

### CRS configuration (`configMapRuleSets` + `coreRuleSet` + inline `ruleSets`)

Same result. Dynamic reload worked correctly with the full combination of all three options, including the OWASP CRS.

### Why no fix was found

A git log inspection confirms there was **no fix** in this area between 1.20.3 and 1.20.6:

- `solo-projects` v1.20.3→v1.20.6: no changes to `projects/gloo/pkg/plugins/waf/`
- `gloo` v1.20.3→v1.20.7 (the dependency range bumped across those releases): only a Go version bump, a go.sum workaround, and an Envoy bump — nothing in the artifact client or ConfigMap watching code

This suggests either the bug does not surface under our test conditions, or it is intermittent/environment-specific. Further investigation should focus on reproducing the customer's exact configuration more closely (e.g. their specific Kubernetes version or the precise combination of `configMapRuleSets` + `coreRuleSet` + `ruleSets` with the full OWASP CRS).

---

## Diagnostics

### WAF blocking messages in gloo-proxy logs

`filter: debug` is configured in `gateways/gatewayparameters.yaml` and applied to the `gw` Gateway via the `gateway.gloo.solo.io/gateway-parameters-name: gatewayparameters` annotation. This is applied as part of `setup.sh`, so WAF debug logging is **always active** in this reproducer — no manual setup required.

To watch blocking events in real time:

```sh
kubectl logs -n ingress-gw deploy/gloo-proxy-gw -f
```

To temporarily toggle the level at runtime without redeploying (POST required, not GET):

```sh
kubectl port-forward -n ingress-gw deploy/gloo-proxy-gw 19000:19000 &
curl -X POST "localhost:19000/logging?filter=info"    # quieten
curl -X POST "localhost:19000/logging?filter=debug"   # re-enable
curl -X POST localhost:19000/logging                  # list all loggers and current levels
```

### Confirm that ConfigMap rules were loaded in gloo-proxy

When a ConfigMap is loaded or reloaded, the `filter` logger emits a `loaded string rule:` message for each rule set. This is the signal that Envoy actually picked up the new rules:

```
[debug][filter] [source/extensions/filters/http/modsecurity/config.cc:93] loaded string rule:
SecRuleEngine On
SecRule REQUEST_HEADERS:X-Bad-Header "@streq blocked" "id:1001,phase:1,deny,status:403,msg:'Blocked by WAF configmap rule'"
SecRule REQUEST_HEADERS:X-Block-Me "@streq true" "id:1002,phase:1,deny,status:403,msg:'Blocked by WAF configmap rule 2'"
```

To watch for this in real time:

```sh
kubectl logs -n ingress-gw deploy/gloo-proxy-gw -f | grep "loaded string rule"
```

If the rules are not reloaded after `kubectl apply`, this line will not appear, confirming the bug.

### Confirm the control plane detected a ConfigMap change

Watch the gloo control plane for a new sync cycle triggered by a ConfigMap update:

```sh
kubectl logs -n gloo-system deploy/gloo -f | grep "begin sync"
```

Each line looks like: `begin sync {hash} (... N artifacts ...)`. A new line with a different hash after `kubectl apply` confirms the change was detected. No new line means the ConfigMap watcher did not fire.
