#!/usr/bin/env bash
#
# backup a folder to internxt (the target folder must already exist on internxt)
# use -h/--help to see usage options
# (by egnrse)

## ====== CONFIG ======
# local_dir: the directory to backup
# target_dir: the destination directory on internxt (must exist already)
local_dir="$1"
target_dir="$2"

## exit status
SUCCESS=0
ERROR=1				# general
ERROR_TARGET_DIR=2	# target dir is invalid or not found
ERROR_CREATE=3		# cant create a file or folder
ERROR_INPUT=5		# bad input args

LOG_LEVEL="${LOG_LEVEL:-1}"	# set log level (0: nothing, 1: basic, 2: info, 3: debug)

## ====== CONSTANTS ======
## internxt (error) messages (for detecting them)
msg_folder_exists="Folder with the same name already exists in this location"
msg_file_exists="File already exists"


## ====== FUNCTIONS ======
# log to stdout (change visiblity with $LOG_LEVEL)
# $1 is the level of a msg
log() {
	[ -z "$1" ] && echo "log(): must have > 0 arguments" >&2 && exit 1
	local level="${1}"
	if [ "$LOG_LEVEL" -ge "$level" ]; then
		shift
		local message="$@"
		local logMsg="[LOG $level]"
		echo -e "$message"
	fi
}

# tests if all given arguments are available as commands
# exits with $ERROR if one is missing
testAvailable() {
	for arg in "$@"; do
		if ! command -v "$arg" >/dev/null 2>&1; then
			echo "'$arg' not installed, but needed." >&2
			exit $ERROR
		fi
	done
}

# prints usage
# expects $1/$2 as arguments (to lookup if they are valid)
usage() {
	echo "usage: $0 source target [options]"
	echo " source: what file/folder to copy"
	echo " target: the destination directory in internxt (must already exist)"
	echo ""
	echo "Options:"
	echo "    -h, --help    show this help message"
	echo ""
	echo "Environment:"
	echo "    LOG_LEVEL     set stdout verbosity (0-5)"
	echo ""
	if [ -z "$2" ] || [ "$2" == "--help" ] || [ "$2" == "-h" ]; then
		echo "(not testing source/target, 'source' or 'target' not provided)"
	else
		echo "Would currently backup '$local_dir' to '$target_dir'"
		if [ -r "$local_dir" ]; then
			echo " source is valid"
		else
			echo " source not found"
		fi
		echo -ne " testing if target is valid..."
		ret_str=$(findFolderID "$target_dir" 2>&1)
		ret_val=$?
		if [ "$ret_val" -eq 0 ]; then
			echo -e "\r target is valid                  "
		else
			echo -e "\r ${ret_str}           "
		fi
	fi
}

# finds the folder ID of the given path $1 starting from $2 (on internxt)
# $1: the target directory, must start with a '/' (eg. '/Backup/PC/')
# $2: is the ID of a folder (will assume root '/' if empty)
findFolderID() {
	local target_dir="$1"
	local start_dir="$2"
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
	local json_ret=$(internxt list --id="${start_dir}" --json --non-interactive)
	if [ $? -ne 0 ] || ! jq -e '.success' <<<"${json_ret}" >/dev/null; then
		echo "$(jq -r '.message'<<<"${json_ret}")" >&2
		return ${ERROR_TARGET_DIR}
	fi

	# get the name of the top folder
	local top_dir="$(awk -F/ '{print $2}'<<<"${target_dir}")"

	if [ -n "${top_dir}" ]; then
		# find the ID of the top folder
		local subfolderID=$(jq -r --arg top_dir "${top_dir}" '.list.folders[] | select(.plainName == $top_dir) | .uuid' <<<"${json_ret}")
		# detect invalid results
		if [ $? -ne 0 ] || [ -z "${subfolderID}" ]; then
			echo "folder '${top_dir}' not found in '${start_dir:-/}'" >&2
			return ${ERROR_TARGET_DIR}
		fi
		
		# get new target path
		rest_dir="${target_dir#*${top_dir}}"

		if [ -n "${rest_dir}" ]; then
			# continue search in the subfolder
			targetID=$(findFolderID "${rest_dir}" "${subfolderID}")
			local returnVal=$?
			if [ $returnVal -ne $SUCCESS ]; then
				echo "${targetID}" >&2
				return $returnVal
			fi
		else
			# use the subfolders ID
			targetID="${subfolderID}"
		fi
	else
		# use this folders ID
		targetID="${start_dir}"
	fi
	echo "${targetID}"
	return $SUCCESS
}

# return the json of a file
# $1: the target file, must start with a '/' (eg. '/Backup/PC/example.txt')
# $2: is the ID of a folder (will assume root '/' if empty)
# returns $SUCCESS on success, the return value of (failed) function calls, else $ERROR
getFileJson() {
	local target="$1"
	local start_dir="$2"
	local targetJson=""	# return value

	# find parent folder id
	local folderID="$(findFolderID "$(dirname "$target")" "$start_dir")"
	local ret_val=$?
	if [ $ret_val -ne $SUCCESS ]; then
		echo "$folderID" >&2
		return $ret_val
	fi

	# list parent folder
	local json_ret
	json_ret="$(internxt list --id="${folderID}" --json --non-interactive)"
	log 5 "getFileJson() json_ret: ${json_ret}" >&2
	if [ $? -ne 0 ] || ! jq -e '.success' <<<"${json_ret}" >/dev/null; then
		echo "$(jq -r '.message'<<<"${json_ret}")" >&2
		return $ERROR
	fi

	# extract the json (from $json_ret)
	local filename="$(basename "$target")"
	local plainname="${filename%.*}"
	local extension="${filename##*.}"
	if [ "$plainname" = "${filename%.}" ]; then
		# deal with extension free files
		targetJson="$(jq -r --arg plainname "${plainname}" --arg ext "${extension}" '.list.files[] | select(.plainName == $plainname and .type == null)'<<<"${json_ret}")"
		ret_val=$?
	else
		targetJson="$(jq -r --arg plainname "${plainname}" --arg ext "${extension}" '.list.files[] | select(.plainName == $plainname and .type == $ext)'<<<"${json_ret}")"
		ret_val=$?
	fi
	if [ $ret_val -ne 0 ] || [ -z "$targetJson" ]; then
		echo "getFileJson(): '\$json_ret' is malformed or \$targetJson is empty" >&2
		return $ERROR
	fi
	echo "$targetJson"
	return $SUCCESS
}

# test if the internxt command worked
# on fail shows the message of the json
exitInternxt() {
	local ret_val="$1"
	local json="$2"
	if [ "$ret_val" -ne 0 ] || ! jq -e '.success' <<<"${json}" >/dev/null; then
		echo "$(jq -r '.message'<<<"${json}")" >&2
		return ${ERROR}
	fi
}

# upload a folder (or a file) to internxt
# $1: local directory (or file) (that should get uploaded)
# $2: the id of the target root folder
copyFolder() {
	local local_dir="$1"
	local target_id="$2"

	# arrays that link local paths to remote folder IDs (they are used to store the current stack of IDs)
	# eg. [0]: $HOME/backup/ (target root), [1]: $HOME/backup/exampledir/, [2]: $HOME/backup/exampledir/subdir/
	parent_array=("${local_dir}")	# a stack of (local) paths
	id_array=("${target_id}")		# the IDs to the equivalent remote folders from the parent_array
	
	find "${local_dir}" -print | while IFS= read -r path; do
		echo "$path"
		
		# detect directory changes (and delete all array entries that are not needed anymore)
		while [ "${#parent_array[@]}" -gt 0 ]; do
			local last="${parent_array[-1]}"
			if [ "$last" = "$path" ] || [ "$(dirname "$last/file")" = "$(dirname "$path")" ]; then
				log 5 "dir changes: found $last"
				break
			else
				log 3 "dir changes: ../"
				unset 'parent_array[-1]'
				unset 'id_array[-1]'
			fi
		done

		if [ -d "$path" ]; then
			## DIRECTORY

			# create directory
			local json_ret="$(internxt create-folder --name="$(basename "$path")" --id=${id_array[-1]} --json --non-interactive)"
			if [ $? -ne 0 ] || ! jq -e '.success' <<<"${json_ret}" >/dev/null; then
				if [ "$(jq -r '.message'<<<${json_ret})" == "$msg_folder_exists" ]; then
					# folder already exists
					local folderName="/$(basename "$path")"
					local uuid="$(findFolderID "${folderName}" ${id_array[-1]})"
					log 1 "  folder '$path' already exists (ID: '$uuid')"
				else
					# other error
					echo "Error: failed to create folder '$path' ($(jq '.message'<<<"${json_ret}"))" >&2
					return ${ERROR_CREATE}
				fi
			else
				local uuid="$(jq -r '.folder.uuid' <<<"${json_ret}")"
				log 1 "  folder created '$path' (ID: '$uuid')"
			fi
			id_array+=("$uuid")
			parent_array+=("$path")
		else
			## FILE

			# upload file
			local json_ret=$(internxt upload-file --file="${path}" --destination="${id_array[-1]}" --json --non-interactive)
			if [ $? -ne 0 ] || ! jq -e '.success' <<<"${json_ret}" >/dev/null; then
				if [ "$(jq -r '.message'<<<"${json_ret}")" == "$msg_file_exists" ]; then
					# file already exists
					local fileName="/$(basename "$path")"
					local json_ret
					json_ret="$(getFileJson "${fileName}" ${id_array[-1]})"
					ret_val=$?
					log 5 "upload file, get json: $json_ret"
					[ "$ret_val" -ne "$SUCCESS" ] && return $ret_val
					local uuid=$(jq -r '.uuid'<<<"${json_ret}")

					local remote_mtime="$(jq -r '.modificationTime'<<<"${json_ret}")"
					remote_mtime="$(date -u -d "$remote_mtime" +%Y-%m-%dT%H:%M:%SZ)" # remove fractional seconds
					local local_mtime="$(date -u -d "$(stat -c %y "$path")" +%Y-%m-%dT%H:%M:%SZ)"
					if [ -z "$remote_mtime" ]; then
						log 1 "  Error: skipping file, failed to get remote time"
					elif [[ "$local_mtime" > "$remote_mtime" ]]; then
						log 1 "  reuploading file: local is newer (ID: '$uuid')"
						log 2 "  local: $local_mtime, remote: $remote_mtime"
						local json_ret="$(internxt trash-file --id="$uuid" --json --non-interactive)"
						exitInternxt $? "$json_ret"
						local json_ret="$(internxt upload-file --file="${path}" --destination="${id_array[-1]}" --json --non-interactive)"
						exitInternxt $? "$json_ret"
					elif [[ "$local_mtime" < "$remote_mtime" ]]; then
						log 1 "  skipping file: local is older (ID: '$uuid')"
						log 2 "  local: $local_mtime, remote: $remote_mtime"
					else
						log 1 "  file: already exists (ID: '$uuid')"
						log 2 "  local: $local_mtime, remote: $remote_mtime"
					fi
				else
					# other error
					echo "Error: failed to upload file '$path' ($(jq '.message'<<<"${json_ret}"))" >&2
					return ${ERROR_CREATE}
				fi
			else
				log 1 "  file uploaded '$path'"
			fi
		fi
	done
}


## ====== PREREQUISITES ======
## test for prerequisites
testAvailable awk jq find basename dirname stat date
if ! command -v internxt > /dev/null; then
	echo "The command 'internxt' is missing. Install it from 'https://github.com/internxt/cli'." >&2
	exit $ERROR
fi
if ! internxt config > /dev/null 2>&1; then
	echo "You need to login first. (with 'internxt login')" >&2
	exit $ERROR
fi


## ====== PROGRAM ======
## handle arguments
for arg in "$@"; do
	case "$arg" in
		-h|--help)
			usage $1 $2
			exit 0
			;;
	esac
done
# test for invalid inputs
if [ -z "$1" ] || [ -z "$2" ]; then
	echo "Error: 'source' and 'target' are required arguments" >&2
	echo ""
	usage $1 $2
	exit $ERROR_INPUT
fi
if [ -n "$3" ]; then
	echo "Error: received unexpexted input '$3'" >&2
	echo ""
	usage $1 $2
	exit $ERROR_INPUT
fi

## find the target directory id
ret_str=$(findFolderID "${target_dir}")
ret_val=$?
if [ ${ret_val} -ne 0 ]; then
	if [ -n "${ret_str}" ]; then
		echo "Error: ${ret_str}" >&2
	fi
	exit ${ret_val}
fi
target_id="${ret_str}"


## copy files/folders
copyFolder $local_dir $target_id
exit $?


#TODO how to handle deleted files?
