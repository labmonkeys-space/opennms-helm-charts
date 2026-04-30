# Contributing

Thanks for your interest in contributing to the OpenNMS Helm Charts.

## Repository conventions

### Chart versioning

`appVersion` in each chart's `Chart.yaml` is the **tested OpenNMS Horizon version**. The four charts (`core`, `sentinel`, `minion`, `opennms-stack`) MUST carry the same `appVersion` because OpenNMS Core, Minion, and Sentinel are released together upstream and share a single version number.

When upstream Horizon ships a new release:

1. Update `appVersion: "<new>"` in `charts/core/Chart.yaml`, `charts/sentinel/Chart.yaml`, `charts/minion/Chart.yaml`, and `charts/opennms-stack/Chart.yaml`.
2. Bump each chart's `version` (chart semver) per the change scope:
   - Patch bump for non-breaking image upgrades.
   - Minor bump for new values keys or behaviour.
   - Major bump for breaking values-schema changes.
3. Bump the strict-pinned subchart versions in `charts/opennms-stack/Chart.yaml` to match the new `core` and `sentinel` versions.
4. Run `helm dep update charts/opennms-stack` to refresh `Chart.lock` and `charts/opennms-stack/charts/`.
5. Run `make readme` to regenerate per-chart `README.md` files via `helm-docs`.

### Strict-pin dependency policy

`charts/opennms-stack/Chart.yaml` uses **exact-version pins** (e.g. `version: 0.2.0`) for its `core` and `sentinel` subchart dependencies. Ranges (`~0.2`, `^0.2`) are forbidden — Core and Sentinel must run the same OpenNMS major version (shared JPA schema, shared Karaf feature set), and a range that quietly pulls a mismatched Sentinel during `helm dep update` is a real footgun.

The trade-off: the umbrella's `version` MUST bump whenever any pinned subchart bumps. CI enforces this via `make lint`.

### Configuration channel

The charts consume container configuration in this order:

1. **Direct env vars** on the runtime container — preferred for everything that has an env-var path (Postgres credentials for Core, JVM opts, JMX exporter, MINION_ID).
2. **Helm-templated etc-overlay** — for Kafka, Elasticsearch, and Sentinel datasource `.cfg` files. Rendered by Helm into a ConfigMap, substituted at pod start by an `envsubst` init container, written to an `emptyDir` mounted at `/opt/<comp>-etc-overlay/etc/`.
3. **Confd is left inert** — the upstream confd YAML overlay is mounted as `{}` so confd's `file` backend has a valid file but produces empty `.cfg` files that the etc-overlay then overwrites.

Do not add configuration via the upstream confd YAML overlay. If you need a `.cfg` file the chart doesn't natively model, use `extraConfigFiles` in values.

### Mixed-content `.cfg` files

For `.cfg` files that mix non-secret values (Kafka brokers, ES URL) and secret values (passwords, SASL credentials), use the existing **envsubst pattern**:

1. Render the `.cfg` template into the `*-config-templates` ConfigMap with `${VAR_NAME}` placeholders.
2. Reference the user's `existingSecret` via env vars on the `render-config` init container (see `*.envsubstEnv` helper in each chart's `_helpers.tpl`).
3. The init container writes the resolved file into the `etc-overlay` `emptyDir`.

Do **not** use Helm's `lookup` function — it fails in `helm template`, `--dry-run`, and ArgoCD diffing.

### Subpath encoding

ConfigMap data keys cannot contain `/`, so subpaths under `etc/` are encoded with `__` in the key name (e.g. `opennms.properties.d__timeseries.properties` lands at `etc/opennms.properties.d/timeseries.properties` after envsubst rendering).

### Linting and testing

```bash
make lint                  # `ct lint` against all four charts
make test-install-core     # `ct install` on Core (needs CNPG)
make test-install-stack    # `ct install` on the umbrella (needs CNPG + Kafka + ES)
```

CI runs all of the above on every push and PR (`.github/workflows/lint-and-test.yaml`).

## Commit conventions

This repository uses [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/). Use `feat`, `fix`, `docs`, `chore`, `ci`, `refactor`, `test`, `build`, `style`, `perf`, `revert` as the type prefix.

When AI tools assist with a commit, attribute via the `Assisted-by` trailer (not `Co-Authored-By`):

```
feat: add prometheus-remote-writer integration

Assisted-by: ClaudeCode:claude-opus-4-7
```

`Signed-off-by` is reserved for the human submitter.

## OpenSpec workflow

Substantial changes go through the OpenSpec workflow under `openspec/`:

```
openspec/changes/<change-name>/
  proposal.md     why & what
  design.md       how — decisions, alternatives, risks
  specs/          requirements + scenarios per capability
  tasks.md        implementation checklist
```

See [`openspec/AGENTS.md`](openspec/AGENTS.md) for the full convention. Use the `/opsx:propose`, `/opsx:apply`, and `/opsx:archive` slash commands when working with Claude Code.
