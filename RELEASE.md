# Release

See [`../ai/RELEASE.md`](../ai/RELEASE.md) for the actual release process
(pre-release checks, versioning, `make tag`/`make dist`, the `stable`
pseudo-version dance, PGXN upload). This file covers only what's genuinely
specific to count_nulls.

## Distribution vs. extension version actually diverged once

`../ai/RELEASE.md` step 3 covers the general PGXN fact that a distribution's
version (`META.in.json`'s top-level `version`) and an extension's version
(`<ext>.control`'s `default_version`) are separate numbers that can differ —
that's not specific to count_nulls. What's specific here is that count_nulls
has actually made use of it: `0.9.7` on PGXN (2017-01-26) was a
distribution-only bump (packaging/CI fixes, no SQL changes) — the extension
version stayed at `0.9.6`, unchanged since 2016. `0.9.7` the *extension*
version has never existed.
