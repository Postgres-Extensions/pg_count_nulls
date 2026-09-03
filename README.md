count_nulls
===========

Provides a function that counts the number of (not) null arguments passed to
it. Also provides a version for counting nulls in a JSON document, which makes
it easy to count the number of nulls in a record.

# Installation #
To build it, just do this:

    make install

If you encounter an error such as:

    "Makefile", line 8: Need an operator

You need to use GNU make, which may well be installed on your system as
`gmake`:

    gmake install

If you encounter an error such as:

    make: pg_config: Command not found

Be sure that you have `pg_config` installed and in your path. If you used a
package management system such as RPM to install PostgreSQL, be sure that the
`-devel` package is also installed. If necessary tell the build process where
to find it:

    env PG_CONFIG=/path/to/pg_config make && make installcheck && make install

And finally, if all that fails (and if you're on PostgreSQL 8.1 or lower, it
likely will), copy the entire distribution directory to the `contrib/`
subdirectory of the PostgreSQL source tree and try it there without
`pg_config`:

    env NO_PGXS=1 make && make installcheck && make install

If you encounter an error such as:

    ERROR:  must be owner of database regression

You need to run the test suite using a super user, such as the default
"postgres" super user:

    make test PGUSER=postgres

Once count_nulls is installed, you can add it to a database. If you're running
PostgreSQL 9.1.0 or greater, it's as simple as connecting to a database and
running:

    CREATE EXTENSION count_nulls;

No superuser required: count_nulls is nothing but SQL functions, so any role
with `CREATE` on the target schema can add it.

If you've upgraded your cluster to PostgreSQL 9.1 and already had count_nulls
installed, you can upgrade it to a properly packaged extension with:

    CREATE EXTENSION count_nulls FROM unpackaged;

For versions of PostgreSQL less than 9.1.0, you'll need to run the
installation script:

    psql -d mydb -f /path/to/pgsql/share/contrib/count_nulls.sql

If you want to install count_nulls and all of its supporting objects into a specific
schema, use the `PGOPTIONS` environment variable to specify the schema, like
so:

    PGOPTIONS=--search_path=extensions psql -d mydb -f count_nulls.sql

Dependencies
------------
The `count_nulls` data type has no dependencies other than PostgreSQL.

Copyright and License
---------------------

Copyright (c) 2015 Jim Nasby, Blue Treble Consulting http://BlueTreble.com

