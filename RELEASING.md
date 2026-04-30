# Releasing

This document is the contract for cutting a release of the OpenNMS Helm
charts in this repository. The release pipeline lives in
[`.github/workflows/release.yaml`](.github/workflows/release.yaml); this
file describes how to drive it.

---

## 1. Conceptual model

The repository ships four Helm charts:

```
charts/core               OpenNMS Horizon Core
charts/sentinel           OpenNMS Sentinel
charts/minion             OpenNMS Minion (deployed per remote location)
charts/opennms-stack      umbrella over Core + Sentinel for the central site
```

Each `Chart.yaml` carries two version fields, and they mean different
things:

- **`appVersion`** is the OpenNMS Horizon release the chart is tested
  against. It is **lock-step across all four charts** — Core, Sentinel,
  and Minion are released together upstream and share a single
  version number; the umbrella inherits the same. When upstream Horizon
  ships a new version, all four charts' `appVersion` ratchet together
  in the same PR.

- **`version`** is independent chart semver, bumped per chart per change
  scope (patch / minor / major). A chart-only edit (e.g., values default
  tuning) bumps just that chart's `version`. An upstream `appVersion`
  bump that touches all four charts bumps all four `version`s.

The umbrella has an extra invariant: **it strict-pins exact subchart
versions**:

```yaml
# charts/opennms-stack/Chart.yaml
dependencies:
  - name: core
    version: "=0.1.0"           ◄── must match charts/core/Chart.yaml
    repository: file://../core
  - name: sentinel
    version: "=0.1.0"           ◄── must match charts/sentinel/Chart.yaml
    repository: file://../sentinel
```

Bumping a subchart's `version` requires bumping the umbrella's pin in
the same PR. The `lint-and-test` workflow has a drift-check step that
runs `helm dep update charts/opennms-stack` against the working tree;
this fails the job at PR-review time if the pins drift.

### Release semantics

- One release event = one tag push of the form `vX.Y.Z` (e.g., `v0.1.0`).
- The tag's version tracks the **umbrella's** chart version, since the
  umbrella's strict-pinned matched-pair invariant makes it the natural
  release marker for the stack as a whole.
- The release workflow packages whichever charts have new versions in
  the tagged commit's `Chart.yaml` files. Charts whose versions are
  already published are skipped silently.
- Two publish targets get the same artifacts:
  - **GitHub Pages** (classic Helm repo, `gh-pages` branch + `index.yaml`)
  - **GHCR** (OCI artifacts at `ghcr.io/labmonkeys-space/charts/<chart>`)

---

## 2. Release-PR checklist

Before tagging, the working tree on `main` must satisfy these:

- [ ] **`appVersion`** is set to the target Horizon version on all four
      charts (`charts/{core,sentinel,minion,opennms-stack}/Chart.yaml`).
- [ ] **`version`** is bumped on every chart whose contents changed since
      the last release, per change scope (patch/minor/major).
- [ ] If `core` or `sentinel`'s `version` changed, `charts/opennms-stack/Chart.yaml`'s
      `dependencies[].version` is updated to match (`"=<new-version>"`).
- [ ] The umbrella's own `version` is bumped if any subchart was bumped
      (the umbrella version reflects the matched set).
- [ ] `helm dep update charts/opennms-stack` runs cleanly, and the
      regenerated `charts/opennms-stack/Chart.lock` is committed.
- [ ] `make readme` runs and the regenerated per-chart `README.md` files
      are committed (helm-docs picks up the new chart-version badges).
- [ ] CI is green on the PR (lint, helm-docs, drift check, all four
      `test-install-*` matrix jobs).
- [ ] PR is merged to `main` before tagging.

---

## 3. Cutting the release

From a clean local checkout of `main`:

```bash
git fetch origin
git checkout main
git pull --ff-only origin main

# The tag's version is the umbrella's chart version.
git tag v0.1.0
git push origin v0.1.0
```

The `release` workflow fires on the tag push. Watch it:

```bash
gh run list --branch main --workflow release --limit 3
gh run watch <run-id>
```

The workflow runs to completion in ~2-3 minutes (no kind cluster, just
`helm package` + `helm push`). On success it has:

- Created a GitHub Release per chart per new version (`core-0.1.0`,
  `sentinel-0.1.0`, `minion-0.1.0`, `opennms-stack-0.1.0`).
- Updated `gh-pages/index.yaml` to include the new entries.
- Pushed each new `.tgz` to GHCR as an OCI artifact.

---

## 4. Verifying the publish

### Helm repository (GitHub Pages)

```bash
helm repo add opennms-helm-charts https://labmonkeys-space.github.io/opennms-helm-charts/
helm repo update
helm search repo opennms-helm-charts
```

Should list all four charts at the new versions.

```bash
helm pull opennms-helm-charts/opennms-stack --version 0.1.0
```

Should download the chart `.tgz` without error.

### OCI registry (GHCR)

```bash
helm show chart oci://ghcr.io/labmonkeys-space/charts/opennms-stack --version 0.1.0
helm pull oci://ghcr.io/labmonkeys-space/charts/opennms-stack --version 0.1.0
```

Both should succeed without auth (GHCR packages are public after the
first-time bootstrap below).

---

## 5. First-time repo bootstrap

These steps run **once per repository**, not per release. After the
first successful release workflow run, follow each of them.

### 5.1. Enable GitHub Pages on the `gh-pages` branch

`chart-releaser-action` creates and pushes to a `gh-pages` branch on
its first run. Only after that branch exists can you turn on Pages
serving:

1. Go to **Settings → Pages** in the GitHub repo UI.
2. Under **Source**, select **Deploy from a branch**.
3. Set **Branch** to `gh-pages`, **Folder** to `/ (root)`. Save.
4. After ~1 minute, `https://labmonkeys-space.github.io/opennms-helm-charts/index.yaml`
   serves the chart index.

### 5.2. Flip GHCR packages from private to public

GHCR creates OCI packages as **private** by default. Anonymous
`helm pull` against a private package fails with auth errors.

For each of the four packages — `charts/core`, `charts/sentinel`,
`charts/minion`, `charts/opennms-stack`:

1. Go to **labmonkeys-space → Packages → `<package-name>`**.
2. **Package settings → Change visibility → Public**.
3. **Manage Actions access → Add Repository → opennms-helm-charts**
   so the workflow can push future versions.

This is done once per package. New versions inherit the visibility.

### 5.3. Confirm workflow permissions

**Settings → Actions → General → Workflow permissions** must be set to
**Read and write permissions**. (This is also required by the
`helm-docs` auto-commit step in `lint-and-test.yaml`, so it's likely
already enabled.)

The release workflow declares its required permissions explicitly at
the job level:

```yaml
permissions:
  contents: write    # GitHub Releases + gh-pages push
  packages: write    # GHCR OCI push
  id-token: write    # reserved for future cosign keyless signing
```

These job-level grants override any repo defaults that are too narrow,
but the repo-level "Read and write" remains the right baseline.

---

## 6. Pre-release identifiers

For release candidates, betas, and other pre-stable channels, use
SemVer pre-release identifiers in both the chart `version` and the
git tag:

```yaml
# charts/opennms-stack/Chart.yaml
version: 0.2.0-rc.1
```

```bash
git tag v0.2.0-rc.1
git push origin v0.2.0-rc.1
```

`chart-releaser-action` handles SemVer pre-release identifiers
natively. Pre-releases publish to the same Pages and OCI targets as
stable releases; users opt in by pinning the version explicitly:

```bash
helm install onms opennms-helm-charts/opennms-stack --version 0.2.0-rc.1
```

`helm search repo opennms-helm-charts` shows pre-releases only with the
`--devel` flag (or `helm search repo opennms-helm-charts --versions`).

---

## 7. Yanking a release

Yanking is informational only — anyone who already pulled the chart
has it cached, and the publish history exists in immutable artifact
trails. Use yanking to stop **future** consumers from picking up a
broken release; do not assume it retroactively unwinds the bad version.

To yank `core-0.2.0`:

1. Delete the GitHub Release `core-0.2.0` from the **Releases** page.
2. On `gh-pages`, edit `index.yaml` to remove the entry for
   `core-0.2.0` (and remove the `.tgz` if it was uploaded as a Pages
   asset — `chart-releaser-action` typically attaches it to the GH
   Release, not the gh-pages branch).
3. Delete the OCI tag:
   ```bash
   gh api -X DELETE \
     repos/labmonkeys-space/opennms-helm-charts/packages/container/charts%2Fcore/versions/<version-id>
   ```
   (Or via the GHCR package settings UI: **Versions → ⋯ → Delete version**.)
4. Publish a follow-up patch release (`core-0.2.1`) with the fix so
   users have a clean upgrade path.

---

## 8. Troubleshooting

**The release workflow ran but no Releases were created.**
Probably every chart's `version` was already published. `chart-releaser`
silently skips charts whose `version` matches an existing GitHub
Release. Check `Chart.yaml` versions in the tagged commit; a forgotten
bump is the usual cause.

**`helm pull oci://…` returns auth errors.**
GHCR package is still private. See §5.2.

**`helm dep update charts/opennms-stack` fails on PR review.**
Strict-pin drift — see §1's "release semantics." Fix:

```bash
# Get the actual subchart versions
grep "^version:" charts/core/Chart.yaml charts/sentinel/Chart.yaml
# Update charts/opennms-stack/Chart.yaml dependencies[].version to match,
# then:
helm dep update charts/opennms-stack
git add charts/opennms-stack/Chart.yaml charts/opennms-stack/Chart.lock
```

**The release workflow failed mid-way; some charts published, some
didn't.**
The two publish legs (Pages, OCI) run in sequence. If the OCI leg
fails, the Pages publish has already happened. Re-tagging the same
version is a no-op for charts already published, so push a patch
release with whatever fix is needed.
