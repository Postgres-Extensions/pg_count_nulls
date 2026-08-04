# lint.mk — thin wrapper; the whole local footprint for consuming
# https://github.com/Postgres-Extensions/linter. Everything else lives in
# the .vendor/linter submodule; see its README for available targets/rules.
.vendor/linter/lint.mk:
	git submodule update --init -- .vendor/linter

include .vendor/linter/lint.mk
