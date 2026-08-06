/*
 * Installs count_nulls once, committed, before the main test/sql/ schedule
 * runs (see pgxntool/README.asc's "test/install" and "Update & Upgrade (U&U)
 * Testing" sections) - so every file under test/sql/ finds it already
 * present instead of each one installing (and dropping) it per-test.
 *
 * This file's own output is NOT tracked as expected output (see
 * test/install/.gitignore): pg_regress resolves both its expected and
 * actual-result paths to test/install/load.out, so the diff is always
 * self-identical regardless of content. Correctness here comes from this
 * file failing loudly (aborting the session) if something's wrong, not
 * from a textual comparison - matching cat_tools' test/install/load.sql.
 */

/*
 * TEST_SCHEMA (the count_nulls.test_schema GUC, set via the Makefile):
 * which schema to install count_nulls into. Empty (the default) means
 * "don't target any schema at all" - lands wherever this session's own
 * default search_path resolves (ordinarily 'public', since test/install
 * runs in its own bare connection, not the in-suite session pgTAP's
 * tap_setup.sql runs in - see phase 1's commit message for why that
 * matters). Non-empty explicitly creates that schema and targets it via
 * CREATE EXTENSION ... WITH SCHEMA below - this file never mutates its
 * own search_path to do so, and not because a one-shot bare connection
 * wouldn't care about a leftover mutation either way: mutating
 * search_path before CREATE EXTENSION would let the install succeed via
 * a coincidentally arranged search_path, masking the extension's own
 * install script secretly depending on unqualified name resolution
 * during install. WITH SCHEMA targets the schema directly without
 * touching search_path at all, so a successful install actually proves
 * the install script itself doesn't need search_path arranged any
 * particular way - the same qualification-correctness principle behind
 * the whole TEST_SCHEMA axis (see core/functions.sql's header and
 * test__check_ncs in sql/extension_tests.sql), just applied to the
 * install step itself rather than to post-install test assertions.
 *
 * Read without missing_ok: a genuinely unpropagated GUC must fail loudly,
 * not be indistinguishable from a deliberately empty one.
 */
SELECT current_setting('count_nulls.test_schema') AS schema
\gset
SELECT :'schema' <> '' AS count_nulls_has_schema
\gset

/*
 * A reusable ' WITH SCHEMA "..."' fragment (leading space included, empty
 * when count_nulls_has_schema is false) so CREATE EXTENSION below can just
 * append :with_schema_clause without repeating the has-schema branch.
 * format() is used unqualified: it's pg_catalog, always resolvable
 * regardless of search_path.
 */
SELECT CASE WHEN :'count_nulls_has_schema'
              THEN format(' WITH SCHEMA %I', :'schema')
              ELSE ''
       END AS with_schema_clause
\gset

\if :count_nulls_has_schema
CREATE SCHEMA IF NOT EXISTS :"schema";
\endif

CREATE EXTENSION count_nulls:with_schema_clause;
