#!/bin/sh
#
# backup some stuff to internxt

# exit status on error
ERROR=1

local_dir="$(pwd)/cloudBackup.sh"
target_dir="/"

if ! command -v internxt > /dev/null; then
	echo "The command 'internxt' is missing. Install it from 'https://github.com/internxt/cli'."
	exit $ERROR
fi
if ! internxt config > /dev/null 2>&1; then
	echo "You need to login first. (with 'internxt login')"
	exit $ERROR
fi

#TODO: find the target folder id with 'internxt list -x --id= --json'
# upload folders (eg with find?)
#internxt upload-file --non-interactive -f ${local_dir} -i ${target_dir}
