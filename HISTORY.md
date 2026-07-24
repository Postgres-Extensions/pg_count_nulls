# count_nulls history

1.0.0
-----

== Fix client_min_messages handling in the install script
CREATE EXTENSION already raises client_min_messages to WARNING for the install
script (only-raising, so a stricter caller is respected) and restores it
afterward - the extension's own `SET client_min_messages = WARNING` was
redundant and, being unconditional, could lower a stricter caller's level
during install. Removed.

0.9.7
-----

Distribution-only release - the extension version itself stayed at `0.9.6`
(see RELEASE.md's note on distribution vs. extension versions). Raised the
minimum supported PostgreSQL version to 9.4 (from 9.3), matching the jsonb
functions added in 0.9.5, and enabled Travis CI.

0.9.6
-----

== Fix functions failing when installed outside the search_path
`null_count()`/`not_null_count()` and their trigger counterparts called each
other unqualified, so installing count_nulls into a schema not on the
caller's search_path broke them. All internal calls are now qualified with
`@extschema@`. Because that qualification is baked into the install script at
`CREATE EXTENSION` time, count_nulls is no longer relocatable
(`relocatable = false`).

0.9.5
-----

== Change null_count()/not_null_count() to return int instead of bigint
Reverted the anyarray variants' return type from bigint (introduced in 0.1.0)
back to int - a count of NULL arguments realistically never approaches
bigint's range.

== Add jsonb support
Added jsonb overloads of `null_count()`/`not_null_count()`; the existing json
overloads now delegate to them via a cast instead of duplicating the
`json_each_text` logic.

0.9.4
-----

Metadata-only release: PostgreSQL's control-file parser rejects comments
inside `prereqs`, which the previous release's `META.in.json` had; fixed, and
documented the PostgreSQL 9.3 requirement.

0.9.3
-----

Adopted pgxntool (https://github.com/decibel/pgxntool) as the project's build
system. No functional changes.

0.9.2
-----

No functional changes - added the first upgrade script (`0.9.0` -> `0.9.2`)
and adjusted where `make dist` writes its distribution zip.

0.9.1
-----

== Add null_count_trigger()/not_null_count_trigger()
Trigger functions for enforcing "this row must have exactly N NULL (or NOT
NULL) columns" as a table constraint, usable via
`CREATE TRIGGER ... EXECUTE PROCEDURE null_count_trigger(N)`.

0.9.0
-----

== Add json support
Added `null_count(json)`/`not_null_count(json)`, counting NULL values across
a JSON object's top-level keys.

0.1.0
-----

Initial release. `null_count()`/`not_null_count()` variadic functions,
counting NULL (or NOT NULL) arguments passed to them.

---

Every entry above from `0.1.0` through `0.9.7` was reconstructed from git
history when this file was created (2026-07-24), not written contemporaneously
with each release - see the corresponding git tags and
https://pgxn.org/dist/count_nulls/ for the authoritative record.
