#!/bin/bash
#
# backup a folder to internxt (the target folder must already exist on internxt)
# (by egnrse)

## ====== CONFIG =======
# local_dir: the directory to backup
# target_dir: the directory on internxt to backup to (must exist already)
local_dir="$(pwd)/"
#local_dir="${HOME}/test/"
target_dir="/Backup/egnrse.eu/"


## ====== SETTINGS ======
## exit status
SUCCESS=0
ERROR=1				# general
ERROR_TARGET_DIR=2	# target dir is invalid or not found
ERROR_CREATE=3		# cant create a file or folder


## ====== PROGRAM ======
## test for prerequisites
if ! command -v internxt > /dev/null; then
	echo "The command 'internxt' is missing. Install it from 'https://github.com/internxt/cli'."
	exit $ERROR
fi
if ! internxt config > /dev/null 2>&1; then
	echo "You need to login first. (with 'internxt login')"
	exit $ERROR
fi
#dev: awk, jq, find, basename, dirname, and more?


# finds the folder ID of the given path $1 starting from $2 (on internxt)
# $1: the target directory, must start with a '/' (eg. '/Backup/PC/')
# $2: is the ID of a folder (will assume root '/' if empty)
findFolderID() {
	local target_dir=$1
	local start_dir=$2
	local targetID=""	# return value

	# sanity checks
	if [ -z "${target_dir}" ]; then
		echo "findFolderID(): '\$target_dir' (\$1) can't be empty" >&2
		return ${ERROR_TARGET_DIR}
	fi
	case "$target_dir" in
		/*) ;;
		*)
			echo "\$target_dir does not start with a '/' ('$target_dir')" >&2
			return ${ERROR_TARGET_DIR}
			;;
	esac

	# list the start folder
	local json_ret=$(internxt list --id=${start_dir} --json --non-interactive)
	if [ $? -ne 0 ] || ! jq -e '.success' <<<${json_ret} >/dev/null; then
		echo "$(jq -r '.message'<<<${json_ret})"
		return ${ERROR_TARGET_DIR}
	fi

	# get the name of the top folder
	local top_dir=$(awk -F/ '{print $2}'<<<${target_dir})

	if [ -n "${top_dir}" ]; then
		# find the ID of the top folder
		local subfolderID=$(jq -r --arg top_dir "${top_dir}" '.list.folders[] | select(.plainName == $top_dir) | .uuid' <<<"${json_ret}")
		# detect invalid results
		if [ $? -ne 0 ] || [ -z "${subfolderID}" ]; then
			echo "folder '${top_dir}' not found in '${start_dir:-/}'"
			return ${ERROR_TARGET_DIR}
		fi
		
		# get new target path
		rest_dir="${target_dir#*${top_dir}}"

		if [ -n "${rest_dir}" ]; then
			# continue search in the subfolder
			targetID=$(findFolderID ${rest_dir} ${subfolderID})
			local returnVal=$?
			if [ $returnVal -ne 0 ]; then
				echo ${targetID}
				return $returnVal
			fi
		else
			# use the subfolders ID
			targetID=${subfolderID}
		fi
	else
		# use this folders ID
		targetID=${start_dir}
	fi
	echo ${targetID}
	return $SUCCESS
}

# upload a folder (or a file) to internxt
# $1: local directory (or file) (that should get uploaded)
# $2: the id of the target root folder
copyFolder() {
	local local_dir=$1
	local target_id=$2

	# arrays that link local paths to remote folder IDs (they are used to store the current stack of IDs)
	# eg. [0]: $HOME/backup/ (target root), [1]: $HOME/backup/exampledir/, [2]: $HOME/backup/exampledir/subdir/
	parent_array=("${local_dir}")	# a stack of (local) paths
	id_array=("${target_id}")		# the IDs to the equivalent remote folders from the parent_array
	
	find "${local_dir}" -print | while IFS= read -r path; do
		echo $path	#dev
		
		# detect directory changes (and delete all array entries that are not needed anymore)
		while [ "${#parent_array[@]}" -gt 0 ]; do
			local last="${parent_array[-1]}"
			if [ "$last" = "$path" ] || [ "$(dirname $last/file)" = "$(dirname $path)" ]; then
				#echo "found $last"
				break
			else
				#echo "../"
				unset 'parent_array[-1]'
				unset 'id_array[-1]'
			fi
		done

		if [ -d "$path" ]; then
			## DIRECTORY
			#dev: test if it exists, add to the arrays

			# create directory
			local json_ret=$(internxt create-folder --name=$(basename $path) --id=${id_array[-1]} --json --non-interactive)
			if [ $? -ne 0 ] || ! jq -e '.success' <<<${json_ret} >/dev/null; then
				echo "Error: failed to create folder '$path' ($(jq '.message'<<<${json_ret}))" >&2
				return ${ERROR_CREATE}
			else
				local uuid=$(jq -r '.folder.uuid' <<<${json_ret})
				echo "  folder created '$path' (ID: '$uuid')"
				id_array+=("$uuid")
				parent_array+=("$path")
			fi
		else
			## FILE
			#dev: test if it exists, overwrite if local is newer

			# upload file
			local json_ret=$(internxt upload-file --file=${path} --destination=${id_array[-1]} --json --non-interactive)
			if [ $? -ne 0 ] || ! jq -e '.success' <<<${json_ret} >/dev/null; then
				echo "Error: failed to upload file '$path' ($(jq '.message'<<<${json_ret}))" >&2
				return ${ERROR_CREATE}
			else
				echo "  file uploaded '$path'"
			fi
		fi
	done
}

## find the target directory id
ret_str=$(findFolderID ${target_dir})
ret_val=$?
if [ ${ret_val} -ne 0 ]; then
	echo "Error: ${ret_str}" >&2
	exit ${ret_val}
fi
target_id=${ret_str}



## copy files/folders
copyFolder $local_dir $target_id
exit $?


#TODO: find the target folder id with 'internxt list -x --id= --json'
# upload folders (eg with find?)
#internxt upload-file --non-interactive -f ${local_dir} -i ${target_dir}

#TODO how to handle deleted files?
