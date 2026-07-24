# Releasing count_nulls

count_nulls builds on pgxntool (https://github.com/Postgres-Extensions/pgxntool);
the release machinery (`make tag`, `make dist`) lives in `pgxntool/base.mk`. These
steps cut a new release.

## 1. Pre-release checks
- [ ] Open issues/PRs for this release reviewed, merged or deferred.
- [ ] CI green on all supported PostgreSQL versions (the `all-checks-passed` job on master).
- [ ] Locally: `make verify-results` passes. It depends on `test` (so it runs the suite
      first, then gates on the results). `make test` alone is non-gating — pgxntool marks
      `installcheck` `.IGNORE`, so it never returns non-zero on a regression; only
      `verify-results` (which inspects `test/regression.diffs`) is a real gate.

## 2. Decide the version and what to track
- [ ] Pick the new version (semantic versioning).
- [ ] Version-specific install scripts (`sql/count_nulls--<version>.sql`) are committed
      directly, not generated from a `.sql.in` source — count_nulls doesn't use pgxntool's
      `.sql.in` machinery, so there's no generated-script-omission choice to make here.
      The update script (`sql/count_nulls--<prev>--<version>.sql`) is ALWAYS committed;
      it's the only thing that makes the update path (`make test-update`) testable.

## 3. Update version + changelog
- [ ] Bump `default_version` in `count_nulls.control` (bumped by hand).
- [ ] Bump the version in `META.in.json` — the source of truth is
      `provides.count_nulls.version` (also update the top-level `version`); `META.json`,
      `control.mk`, and `meta.mk` (which feeds `PGXNVERSION`) regenerate via `make`.
- [ ] Advance `release_status` in `META.in.json` as appropriate (unstable → testing →
      stable).
- [ ] Add the update script `sql/count_nulls--<prev>--<version>.sql`; confirm
      `ALTER EXTENSION count_nulls UPDATE` from the previous version reaches the new
      version, on multiple PG majors. `make test-update` exercises this directly — it
      installs the oldest still-tracked version (currently `0.9.6`) and updates to
      current, running the full suite against the result.

## 4. Verify
- [ ] `make verify-results` green (it runs `test` first, then gates on the results).
- [ ] `make test-update` green — confirms the update path, not just a fresh install.
- [ ] From a clean checkout (or `git archive` of the tag): `make && make install`
      regenerates and installs cleanly and `CREATE EXTENSION count_nulls;` reports the
      new version — confirms a PGXN consumer can build from the tracked sources alone.
      (This mirrors what `make dist` ships, since it archives the tag: committed files
      only.)

## 5. Tag and distribute
- [ ] Commit the release changes; working tree must be clean — `make tag` aborts with
      "Untracked changes!" on a dirty tree.
- [ ] `make tag` — creates a git tag named exactly the version, UNPREFIXED (e.g. `1.0.1`,
      no `v` prefix), taken from `PGXNVERSION`, and pushes it to `origin`. It is
      idempotent when the tag already points at HEAD, and errors if the tag exists on a
      different commit. To move an existing tag use `make forcetag` (= `make rmtag` then
      `make tag`); `make rmtag` deletes the tag locally and on `origin`.
- [ ] `make dist` — depends on `tag` (and builds the HTML docs), then
      `git archive`s the tag into `../count_nulls-<version>.zip` (parent directory).
      Because it archives the tag, only committed files are included. If a
      `.gitattributes` exists it must be committed, or `dist` aborts (git archive only
      honors `export-ignore` for committed files). `make forcedist` = `forcetag` + `dist`.
- [ ] Upload the `../count_nulls-<version>.zip` to PGXN (manual).
