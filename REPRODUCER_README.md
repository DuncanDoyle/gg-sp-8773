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

### Scripts (run from the `install/` directory)

| Script | Action |
|---|---|
| `setup-waf-simple.sh` | Apply config-1 + simple VHO |
| `setup-waf-complex.sh` | Apply config-1 + complex VHO |
| `configure-waf-1.sh` | Switch to config-1 (1 rule) |
| `configure-waf-2.sh` | Switch to config-2 (2 rules) |
| `remove-waf-simple.sh` | Delete ConfigMaps + simple VHO |
| `remove-waf-complex.sh` | Delete ConfigMaps + complex VHO |

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

## Findings

**Gloo Gateway 1.20.6 — bug NOT reproduced in either configuration.**

### Simple configuration (`configMapRuleSets` only)

Switching from config-1 to config-2 via `kubectl apply` was reflected immediately in gloo-proxy. The `X-Block-Me: true` rule became active without a delete/recreate cycle.

### Complex configuration (`configMapRuleSets` + inline `ruleSets`)

Same result. Dynamic reload worked correctly when `configMapRuleSets` was combined with an inline `ruleSets` entry.

### Why no fix was found

A git log inspection confirms there was **no fix** in this area between 1.20.3 and 1.20.6:

- `solo-projects` v1.20.3→v1.20.6: no changes to `projects/gloo/pkg/plugins/waf/`
- `gloo` v1.20.3→v1.20.7 (the dependency range bumped across those releases): only a Go version bump, a go.sum workaround, and an Envoy bump — nothing in the artifact client or ConfigMap watching code

This suggests either the bug does not surface under our test conditions, or it is intermittent/environment-specific. Further investigation should focus on reproducing the customer's exact configuration more closely (e.g. their specific Kubernetes version or the precise combination of `configMapRuleSets` + `coreRuleSet` + `ruleSets` with the full OWASP CRS).
