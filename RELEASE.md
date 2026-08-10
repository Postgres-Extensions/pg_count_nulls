# Release

See [`../ai/RELEASE.md`](../ai/RELEASE.md) for the actual release process
(pre-release checks, versioning, `make tag`/`make dist`, the `stable`
pseudo-version dance, PGXN upload). This file covers only what's genuinely
specific to count_nulls.

## Distribution vs. extension version

count_nulls is one of the repos that tracks two version numbers which can
differ: the **distribution version** (`META.in.json`'s top-level `version`,
what PGXN.org lists a release under) and the **extension version**
(`count_nulls.control`'s `default_version`, what `CREATE EXTENSION
count_nulls;` installs by default and what `pg_extension.extversion`
reports). They're usually bumped together, but count_nulls has already
shipped a release where they weren't: `0.9.7` on PGXN (2017-01-26) was a
distribution-only bump (packaging/CI fixes, no SQL changes) — the extension
version stayed at `0.9.6`, unchanged since 2016. `0.9.7` the *extension*
version has never existed.
