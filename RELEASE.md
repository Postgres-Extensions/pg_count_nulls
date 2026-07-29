# Release

This extension makes use of pgxntool (https://github.com/Postgres-Extensions/pgxntool);
the release machinery (`make tag`, `make dist`) lives in `pgxntool/base.mk`. These
steps cut a new release.

Two version numbers matter here and they can differ: the **distribution version**
(`META.in.json`'s top-level `version`, feeds `PGXNVERSION`, what PGXN.org lists a
release under) and the **extension version** (`count_nulls.control`'s
`default_version`, what `CREATE EXTENSION count_nulls;` installs by default and
what `pg_extension.extversion` reports). They're usually bumped together, but
count_nulls has already shipped a release where they weren't: `0.9.7` on PGXN
(2017-01-26) was a distribution-only bump (packaging/CI fixes, no SQL changes) —
the extension version stayed at `0.9.6`, unchanged since 2016. `0.9.7` the
*extension* version has never existed.

## 1. Safety check: verify committed version files haven't drifted

Before anything else, confirm every committed versioned install script still
matches what that version actually shipped — this is the check that the
`stable`-vs-real-version dance (step 4/7 below) exists to make routine, but
it's worth a direct look before relying on it.

- [ ] For each versioned install script, find its last-touching commit:
      `git log -1 --format='%H %ad' -- sql/<extension>--<version>.sql`.
- [ ] Confirm that commit is no later than when that EXTENSION version actually
      shipped. `git tag` is the authoritative source for this once the project
      is on a tag-based release history. If any releases predate that (tracked
      some other way, e.g. release branches, or not tracked at all), fall back
      to cross-checking the extension's PGXN.org listing, remembering that it
      lists *distribution* versions, which can lag the extension version they
      contain (see the `0.9.7` example above).
- [ ] A version file touched by a commit LATER than its own release is a red
      flag — it likely means `default_version` was left pointing at a real
      (non-`stable`) version and a later source edit silently regenerated
      (corrupted) it. Investigate before proceeding.
- [ ] **Known exception, not necessarily a corruption:** a version file whose
      last-touching commit is much later than its version's real release can
      also mean the file was legitimately backfilled after the fact (e.g. a
      newer pgxntool version started requiring committed version files that
      weren't tracked before). A late add-date alone isn't suspicious — only
      worry about a file whose *content* looks like it might differ from what
      actually shipped.

## 2. Pre-release checks
- [ ] Open issues/PRs for this release reviewed, merged or deferred.
- [ ] CI green on all supported PostgreSQL versions.
- [ ] Locally: `make verify-results` passes. It depends on `test` (so it runs the suite
      first, then gates on the results). `make test` alone is non-gating — pgxntool marks
      `installcheck` `.IGNORE`, so it never returns non-zero on a regression; only
      `verify-results` (which inspects `test/regression.diffs`) is a real gate.

## 3. Decide the version and what to track
- [ ] Pick the new version (semantic versioning). Decide whether the extension
      version needs to move at all, or (per the `0.9.7` example above) only the
      distribution version does, if this release has no SQL changes.
- [ ] **Default to committing every versioned install script.** For a small
      extension (a handful of tracked versions, a source file measured in
      dozens of lines rather than thousands), the storage cost of keeping
      every version's file is negligible — there's little reason to skip it
      purely to save space. The update-test-coverage value (being able to
      install any prior version and `ALTER EXTENSION UPDATE` from it) is the
      same regardless of size; only skip committing a version's install
      script for a truly trivial change where you've already decided that
      coverage isn't worth even the small cost. Update scripts (following the
      `sql/<extension>--<prev>--<version>.sql` naming) are ALWAYS committed
      regardless — they're the only thing that makes the update path
      testable at all.

## 4. Update version + changelog

> **⚠️ CRITICAL — you are temporarily leaving the `stable` pseudo-version.** Master's
> `default_version` (in the extension's `.control` file) normally sits at the literal
> string `'stable'`, so that ordinary source edits regenerate the current install
> script (via the existing rule in `control.mk`, driven by whatever `default_version`
> says) and never touch a frozen, already-shipped version's file. Stamping a real
> version number here points that same generation rule at the real version's install
> script instead. The moment this release is merged you **MUST** flip `default_version`
> back to `stable` (step 7) if the extension version moved. If you forget, the next
> source edit on master will regenerate — and corrupt — the just-released version's
> install file.

- [ ] If the extension version is moving, bump `default_version` in the `.control`
      file (bumped by hand). If only the distribution version is moving (no SQL
      changes — see step 3), leave `default_version` alone.
- [ ] Bump the version in `META.in.json` — the source of truth is the top-level
      `version` (the distribution version; always bump this) and the extension's
      own entry under `provides` (the extension version; only bump if it's
      actually moving, per step 3). `META.json`, `control.mk`, and `meta.mk`
      (which feeds `PGXNVERSION`) regenerate via `make`.
- [ ] Advance `release_status` in `META.in.json` as appropriate (unstable → testing →
      stable).
- [ ] If the extension version moved: add the update script from the previous
      version to the new one; confirm the `ALTER EXTENSION UPDATE` path
      actually reaches the new version from the previous one, on multiple PG
      majors.
- [ ] Stamp `HISTORY.md`: the top `stable` section accumulates user-facing changes as
      PRs land; at release, rename that header to the new (distribution) version
      number.

## 5. Verify
- [ ] `make verify-results` green (it runs `test` first, then gates on the results).
- [ ] From a clean checkout (or `git archive` of the tag): `make && make install`
      regenerates and installs cleanly, and creating the extension reports the
      expected version — confirms a PGXN consumer can build from the tracked sources
      alone. (This mirrors what `make dist` ships, since it archives the tag:
      committed files only.)

## 6. Tag and distribute
- [ ] Commit the release changes; working tree must be clean — `make tag` aborts with
      "Untracked changes!" on a dirty tree.
- [ ] `make tag` — creates a git tag named exactly the DISTRIBUTION version,
      UNPREFIXED (e.g. `1.0.0`, no `v` prefix), taken from `PGXNVERSION`, and pushes
      it to `upstream` (this project's `Makefile` sets `PGXN_REMOTE = upstream`,
      since `origin` here is the `jnasbyupgrade` fork, not the canonical repo — see
      pgxntool#53). If this project has used a different release-tracking scheme
      before (release branches, no tracking at all, etc.), `make tag` is the sole
      mechanism going forward once migrated. It's idempotent when the tag already
      points at HEAD, and errors if the tag exists on a different commit. To move
      an existing tag use `make forcetag` (= `make rmtag` then `make tag`);
      `make rmtag` deletes the tag locally and on `upstream`.
- [ ] `make dist` — depends on `tag` (and builds the HTML docs), then
      `git archive`s the tag into a distribution zip in the parent directory.
      Because it archives the tag, only committed files are included. If a
      `.gitattributes` exists it must be committed, or `dist` aborts (git archive only
      honors `export-ignore` for committed files). `make forcedist` = `forcetag` + `dist`.
- [ ] Upload the resulting zip to PGXN (manual).

## 7. Return master to `stable` (CRITICAL — do not skip, if the extension version moved)
- [ ] As soon as the release is merged, flip `default_version` back to `stable` in
      the `.control` file, open a new top `stable` section in `HISTORY.md`, and
      re-seed a fresh update script from this release to `stable` (content-identical
      to the source at this point — it exists purely so the update path to `stable`
      is always available) for the next cycle. Leaving master stamped at the real
      version means the next source edit regenerates and corrupts the released
      version's install file.
- [ ] Keep this PR's description small — something like "Reset version back to
      `stable` after release." is enough. It's a mechanical, low-risk step; it
      doesn't need the detailed rationale a real content change would.
