#!/usr/bin/env bash

#
# Copyright (c) 2018, Postgres Professional
#
# supported levels:
#		* standard
#		* scan-build
#		* hardcore
#		* nightmare
#

set -ux
status=0

# global exports
export PGPORT=55435
export VIRTUAL_ENV_DISABLE_PROMPT=1

# rebuild PostgreSQL with cassert + valgrind support
if [ "$LEVEL" = "hardcore" ] || \
   [ "$LEVEL" = "nightmare" ]; then

	set -e

	CUSTOM_PG_BIN=$PWD/pg_bin
	CUSTOM_PG_SRC=$PWD/postgresql

	# here PG_VERSION is provided by postgres:X-alpine docker image
	curl "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2" -o postgresql.tar.bz2
	echo "$PG_SHA256 *postgresql.tar.bz2" | sha256sum -c -

	mkdir $CUSTOM_PG_SRC

	tar \
		--extract \
		--file postgresql.tar.bz2 \
		--directory $CUSTOM_PG_SRC \
		--strip-components 1

	cd $CUSTOM_PG_SRC

	# enable Valgrind support
	sed -i.bak "s/\/* #define USE_VALGRIND *\//#define USE_VALGRIND/g" src/include/pg_config_manual.h

	# enable additional options
	./configure \
		CFLAGS='-Og -ggdb3 -fno-omit-frame-pointer' \
		--enable-cassert \
		--prefix=$CUSTOM_PG_BIN \
		--quiet

	# build & install PG
	time make -s -j$(nproc) && make -s install

	# build & install FDW
	time make -s -C contrib/postgres_fdw -j$(nproc) && \
		 make -s -C contrib/postgres_fdw install

	# override default PostgreSQL instance
	export PATH=$CUSTOM_PG_BIN/bin:$PATH
	export LD_LIBRARY_PATH=$CUSTOM_PG_BIN/lib

	# show pg_config path (just in case)
	which pg_config

	cd -

	set +e
fi

# show pg_config just in case
pg_config

# perform code checks if asked to
if [ "$LEVEL" = "scan-build" ] || \
   [ "$LEVEL" = "hardcore" ] || \
   [ "$LEVEL" = "nightmare" ]; then

	# perform static analyzis
	scan-build --status-bugs make USE_PGXS=1 || status=$?

	# something's wrong, exit now!
	if [ $status -ne 0 ]; then exit 1; fi

	# don't forget to "make clean"
	make USE_PGXS=1 clean
fi


# build and install extension (using PG_CPPFLAGS and SHLIB_LINK for gcov)
make USE_PGXS=1 PG_CPPFLAGS="-coverage" SHLIB_LINK="-coverage"
make USE_PGXS=1 install
