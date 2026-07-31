-- Installs count_nulls once, committed, before the main test/sql/ schedule
-- runs (see pgxntool/README.asc's "test/install" and "Update & Upgrade (U&U)
-- Testing" sections) - so every test/sql/*.sql file finds it already
-- present instead of each one installing (and dropping) it per-test.
--
-- This file's own output is NOT tracked as expected output (see
-- test/install/.gitignore): pg_regress resolves both its expected and
-- actual-result paths to test/install/load.out, so the diff is always
-- self-identical regardless of content. Correctness here comes from this
-- file failing loudly (aborting the session) if something's wrong, not
-- from a textual comparison - matching cat_tools' test/install/load.sql.

/*
 * TEST_SCHEMA (the count_nulls.test_schema GUC, set via the Makefile):
 * which schema to install count_nulls into. Empty (the default) means
 * "don't target any schema at all" - lands wherever this session's own
 * default search_path resolves (ordinarily 'public', since test/install
 * runs in its own bare connection, not the in-suite session pgTAP's
 * tap_setup.sql runs in - see phase 1's commit message for why that
 * matters). Non-empty explicitly creates and targets that schema.
 *
 * Read without missing_ok: a genuinely unpropagated GUC must fail loudly,
 * not be indistinguishable from a deliberately empty one.
 */
SELECT current_setting('count_nulls.test_schema') AS schema
\gset
SELECT :'schema' <> '' AS count_nulls_has_schema
\gset

\if :count_nulls_has_schema
CREATE SCHEMA IF NOT EXISTS :"schema";
SET search_path = :"schema";
\endif

CREATE EXTENSION count_nulls;
