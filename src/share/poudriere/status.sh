#!/bin/sh
# 
# Copyright (c) 2013 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

usage() {
	cat << EOF
poudriere status [options]

Options:
    -a          -- Show all builds, not just running. This is default
                   if -B is specified.
    -b          -- Display status of each builder for the matched build.
    -B name     -- What buildname to use (must be unique, defaults to
                   "latest")
    -j name     -- Run on the given jail
    -p tree     -- Specify on which ports tree to match for the build.
    -l          -- Show logs instead of URL.
    -H          -- Script mode. Do not print headers and separate fields by a
                   single tab instead of arbitrary white space.
    -z set      -- Specify which SET to match for the build. Use '0' to only
                   match on empty sets.
EOF
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`

PTNAME=
SETNAME=
BUILDNAME=latest
SCRIPT_MODE=0
ALL=0
URL=1
BUILDER_INFO=0

. ${SCRIPTPREFIX}/common.sh

while getopts "abB:j:lp:Hz:" FLAG; do
	case "${FLAG}" in
		a)
			ALL=1
			;;
		b)
			BUILDER_INFO=1
			;;
		B)
			BUILDNAME="${OPTARG}"
			ALL=1
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		l)
			URL=0
			;;
		p)
			PTNAME=${OPTARG}
			;;
		H)
			SCRIPT_MODE=1
			;;
		z)
			SETNAME="${OPTARG}"
			;;
		*)
			usage
			;;
	esac
done

shift $((OPTIND-1))

ORIG_BUILDNAME="${BUILDNAME}"

if [ ${ALL} -eq 0 ] && \
    [ $(find ${POUDRIERE_DATA}/build -mindepth 2 -maxdepth 2 2>&1 | wc -l) \
	-eq 0 ] ; then
	[ ${SCRIPT_MODE} -eq 0 ] && msg "No running builds. Use -a to show all."
	exit 0
fi

POUDRIERE_BUILD_TYPE=bulk
now="$(date +%s)"

if [ ${SCRIPT_MODE} -eq 0 ] ; then
	[ ${ALL} -eq 0 ] && \
	    msg "==> Only showing running builds Use -a to show all."
	[ -n "${JAILNAME}" -a ${BUILDER_INFO} -eq 0 ] && \
	    msg "==> Use -b to show detailed builder output."
fi

if [ ${SCRIPT_MODE} -eq 0 -a ${BUILDER_INFO} -eq 0 ]; then
	format="%-40s %-25s %6s %5s %6s %7s %7s %7s %9s %s"
	printf "${format}" "JAIL" "STATUS" "QUEUED" \
	    "BUILT" "FAILED" "SKIPPED" "IGNORED" "TOBUILD" \
	    "TIME"
	if [ -n "${URL_BASE}" ] && [ ${URL} -eq 1 ]; then
		echo -n "URL"
	else
		echo -n "LOGS"
	fi
	echo
else
	format="%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s"
fi
for mastermnt in ${POUDRIERE_DATA}/logs/bulk/*; do
	# Check empty dir
	case "${mastermnt}" in
		"${POUDRIERE_DATA}/logs/bulk/*") break ;;
	esac
	MASTERNAME=${mastermnt#${POUDRIERE_DATA}/logs/bulk/}
	# Skip non-running on ALL=0
	[ ${ALL} -eq 0 ] && ! jail_runs ${MASTERNAME} && continue
	# Dereference latest into actual buildname
	BUILDNAME="$(BUILDNAME="${ORIG_BUILDNAME}" bget buildname 2>/dev/null || :)"
	# No matching build, skip.
	[ -z "${BUILDNAME}" ] && continue
	if [ -n "${JAILNAME}" ]; then
		jailname=$(bget jailname)
		[ "${jailname}" = "${JAILNAME}" ] || continue
	fi
	if [ -n "${PTNAME}" ]; then
		ptname=$(bget ptname)
		[ "${ptname}" = "${PTNAME}" ] || continue
	fi
	if [ -n "${SETNAME}" ]; then
		setname=$(bget setname)
		[ "${setname}" = "${SETNAME%0}" ] || continue
	fi

	if [ ${BUILDER_INFO} -eq 0 ]; then
		status=$(bget status 2>/dev/null || :)
		nbqueued=$(bget stats_queued 2>/dev/null || :)
		nbfailed=$(bget stats_failed 2>/dev/null || :)
		nbignored=$(bget stats_ignored 2>/dev/null || :)
		nbskipped=$(bget stats_skipped 2>/dev/null || :)
		nbbuilt=$(bget stats_built 2>/dev/null || :)
		nbtobuild=$((nbqueued - (nbbuilt + nbfailed + nbskipped + nbignored)))

		log="$(log_path)"
		calculate_elapsed ${now} ${log}
		elapsed=${_elapsed_time}
		time=$(date -j -u -r ${elapsed} "+%H:%M:%S")

		if [ -n "${URL_BASE}" ] && [ ${URL} -eq 1 ]; then
			url="${URL_BASE}/${POUDRIERE_BUILD_TYPE}/${MASTERNAME}/${BUILDNAME}"
		else
			url="${log}"
		fi
		printf "${format}\n" "${MASTERNAME}" "${status}" "${nbqueued}" \
			"${nbbuilt}" "${nbfailed}" "${nbskipped}" "${nbignored}" \
			"${nbtobuild}" "${time}" "${url}"
	else

		builders="$(bget builders 2>/dev/null || :)"

		JOBS="${builders}" siginfo_handler
	fi
done
