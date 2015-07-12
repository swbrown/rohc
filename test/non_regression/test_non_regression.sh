#!/bin/sh
#
# Copyright 2010,2012,2013,2014 Viveris Technologies
# Copyright 2010,2011,2012,2013,2015 Didier Barvaux
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
#

#
# file:        test_non_regression.sh
# description: Check that the behaviour of the ROHC library did not changed
#              without developpers noticing it.
# authors:     Didier Barvaux <didier.barvaux@toulouse.viveris.com>
#              Didier Barvaux <didier@barvaux.org>
#
# This script may be used by creating a link "test_non_regression_maxcontextsN_wlsbM_CIDTYPE_STREAM.sh"
# where:
#    N       is the maximum number of contexts the ROHC library may use
#    M       is the width of the W-LSB window the ROHC library shall use
#    CIDTYPE is the type of CID the ROHC library shall use
#    STREAM  is the path to the capture file that contains the IP stream to
#            test library with (separators '/' are replaced by '_')
#
# Script arguments:
#    test_non_regression_maxcontextsN_wlsbM_CIDTYPE_STREAM.sh [verbose]
# where:
#   verbose          prints the traces of test application
#
# Environment variables:
#    USE_VALGRIND=yes|no   run the tests within Valgrind or not
#    USE_PYTHON=yes|no     run the tests of the Python binding or not
#

# skip test in case of cross-compilation
if [ "${CROSS_COMPILATION}" = "yes" ] && \
   [ -z "${CROSS_COMPILATION_EMULATOR}" ] ; then
	exit 77
fi

test -z "${SED}" && SED="`which sed`"
test -z "${GREP}" && GREP="`which grep`"
test -z "${AWK}" && AWK="`which gawk`"
test -z "${AWK}" && AWK="`which awk`"

# parse arguments
SCRIPT="$0"
VERBOSE="$1"
if [ "x$MAKELEVEL" != "x" ] ; then
	BASEDIR="${srcdir}"
	APP="../test_non_regression${KERNEL_SUFFIX}${CROSS_COMPILATION_EXEEXT}"
	APP_PYTHON="../../../contrib/python/test_non_regression.py"
else
	BASEDIR=$( dirname "${SCRIPT}" )
	APP="${BASEDIR}/../test_non_regression${KERNEL_SUFFIX}${CROSS_COMPILATION_EXEEXT}"
	APP_PYTHON="${BASEDIR}/../../../contrib/python/test_non_regression.py"
fi

# extract the CID type and capture name from the name of the script
PARAMS=$( echo "${SCRIPT}" | \
          ${SED} -e 's#^.*/test_non_regression_##' -e 's#\.sh$##' )
MAX_CONTEXTS=$( echo "${PARAMS}" | ${AWK} -F'_' '{ print $(NF-2) }' | sed -e 's/maxcontexts//' )
WLSB_WIDTH=$( echo "${PARAMS}" | ${AWK} -F'_' '{ print $(NF-1) }' | sed -e 's/wlsb//' )
CID_TYPE=$( echo "${PARAMS}" | ${AWK} -F'_' '{ print $(NF) }' )
STREAM=$( echo "${PARAMS}" | ${AWK} -F'_' '{ OFS="/" ; $(NF-2)="" ; $(NF-1)="" ; $(NF)="" ; print $0 }' )
CAPTURE_SOURCE="${BASEDIR}/inputs/${STREAM}/source.pcap"
CAPTURE_COMPARE="${BASEDIR}/inputs/${STREAM}/rohc_maxcontexts${MAX_CONTEXTS}_wlsb${WLSB_WIDTH}_${CID_TYPE}.pcap"
SIZE_COMPARE="${BASEDIR}/inputs/${STREAM}/rohc_maxcontexts${MAX_CONTEXTS}_wlsb${WLSB_WIDTH}_${CID_TYPE}.sizes"

# check that capture names are not empty
if [ -z "${CAPTURE_SOURCE}" ] ; then
	echo "empty source capture name, please do not run $0 directly!"
	exit 1
fi
if [ ! -f "${CAPTURE_SOURCE}" ] ; then
	echo "source capture '${CAPTURE_SOURCE}' not found!"
	exit 1
fi
if [ -z "${CAPTURE_COMPARE}" ] ; then
	echo "empty compare capture name, please do not run $0 directly!"
	exit 1
fi
if [ "${VERBOSE}" != "generate" ] && [ ! -f "${CAPTURE_COMPARE}" ] ; then
	echo "compare capture '${CAPTURE_COMPARE}' not found!"
	exit 1
fi
if [ "${VERBOSE}" != "generate" ] && [ ! -f "${SIZE_COMPARE}" ] ; then
	echo "file with compare sizes '${SIZE_COMPARE}' not found!"
	exit 1
fi

# determine the maximum number of contexts if MAX_CONTEXTS == 0
if [ ${MAX_CONTEXTS} -eq 0 ] ; then
	if [ "${CID_TYPE}" = "smallcid" ] ; then
		MAX_CONTEXTS=16
	else
		MAX_CONTEXTS=16384
	fi
fi

APP="${CROSS_COMPILATION_EMULATOR} ${APP}"
CMD_PYTHON="${APP_PYTHON}"
if [ -n "${KERNEL_SUFFIX}" ] ; then
	# normal mode for kernel: compare with existing ROHC output captures
	CMD="${APP} -c ${CAPTURE_COMPARE} ${CAPTURE_SOURCE}"
elif [ "${VERBOSE}" = "generate" ] ; then
	# generate ROHC output captures
	CMD="${APP} -o ${CAPTURE_COMPARE} --rohc-size-output ${SIZE_COMPARE}"
	CMD="${CMD} --wlsb-width ${WLSB_WIDTH}"
	CMD="${CMD} --max-contexts ${MAX_CONTEXTS}"
	CMD="${CMD} ${CID_TYPE} ${CAPTURE_SOURCE}"
else
	# normal mode: compare with existing ROHC output captures
	CMD_PARAMS="${CMD_PARAMS} --wlsb-width ${WLSB_WIDTH}"
	CMD_PARAMS="${CMD_PARAMS} --max-contexts ${MAX_CONTEXTS}"
	CMD_PARAMS="${CMD_PARAMS} ${CID_TYPE} ${CAPTURE_SOURCE}"
	if [ "${VERBOSE}" = "verbose" ] ; then
		CMD_PARAMS="${CMD_PARAMS} --verbose"
	fi
	CMD="${APP} ${CMD_PARAMS} -c ${CAPTURE_COMPARE}"
	CMD_PYTHON="${CMD_PYTHON} ${CMD_PARAMS} -c ${CAPTURE_COMPARE}"
fi

# source valgrind-related functions
. ${BASEDIR}/../../valgrind.sh

# C or Pyhton test?
if [ -z "${USE_PYTHON}" ] || [ "${USE_PYTHON}" != "yes" ] ; then
	# run C tests

	# run without valgrind
	run_test_without_valgrind ${CMD} || exit $?

	[ "${VERBOSE}" = "generate" ] && exit 77

	# run Valgrind tests if they are enabled
	if [ "${USE_VALGRIND}" = "yes" ] ; then
		# tests with Valgrind are not possible in the Linux kernel
		[ -n "${KERNEL_SUFFIX}" ] && exit 0
		# run with valgrind in verbose mode or quiet mode
		run_test_with_valgrind ${BASEDIR}/../../valgrind.xsl ${CMD} || exit $?
	fi

elif [ "${USE_PYTHON}" = "yes" ] ; then
	# run Python tests

	# tests with Python are not possible in the Linux kernel
	[ -n "${KERNEL_SUFFIX}" ] && exit 77
	# generation is not possible with Python tests
	[ "${VERBOSE}" = "generate" ] && exit 77

	# run python bindings without valgrind
	root_dir="${BASEDIR}/../../../"
	export LD_LIBRARY_PATH="${root_dir}/src/.libs/:${root_dir}/contrib/python/build/lib.linux-x86_64-2.7"
	export PYTHONPATH="${root_dir}/contrib/python/build/lib.linux-x86_64-2.7"
	run_test_without_valgrind ${CMD_PYTHON} || exit $?

else
	# not C nor Python: unknown tests
	exit 77
fi

