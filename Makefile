include pgxntool/base.mk

# Temporary hack
testdeps: $(wildcard test/*/*.sql) $(wildcard test/*.sql) # Be careful not to include directories in this

# pgxntool/base.mk unconditionally adds --load-language=plpgsql, but pg_regress
# on PG13+ rejects that flag outright. Drop it until pgxntool is updated to
# gate the flag by PG version itself.
ifeq ($(call test, $(MAJORVER), -ge, 130), yes)
REGRESS_OPTS = --inputdir=$(TESTDIR) --outputdir=$(TESTOUT)
endif
