#!/bin/bash

## e621 pool downloader.

## Core functions. Functions used to simplify common tasks.
# fetch function. This runs a curl request with the proper user-agent.
function fetch() {
	userAgent="PoolDownloader/0.01 (by Shelrock; pd@angelgarcia.dev) Curl"

	if [[ $(echo "$sessionCookie") ]]; then
		curl -A "$userAgent" -b "$sessionCookie" -f $* 2>/dev/null
	else
		curl -A "$userAgent" -f $* 2>/dev/null
	fi
}

# lnsay function. Print a line and allow it to be overwriten. Intended to be used in loops.
function lnsay() {
	prf=$(echo "$*");
	cols=$(($(tput cols)-1))
	printf "\r\033[0K""${prf:0:$cols}"
}

## Procedure functions. "The script itself".
# buildMeta function. Create the working directory and get the metadata for the given poolId.
function buildMeta() {
	lnsay "Fetching meta for pool $*"

	# Fetch the pool metadata. Also, a projection discarrd irrelevant data.
	fetch "https://e621.net/pools/$*.json" |jq '{id, name, post_count, post_ids}' >/tmp/e621downloader/$*.json

	# Common vars used in the function.
	poolId=$(cat "/tmp/e621downloader/$*.json" |jq -r .id)
	poolName=$(cat "/tmp/e621downloader/$*.json" |jq -r .name |tr "_" " ")
	postCount=$(cat "/tmp/e621downloader/$*.json" |jq -r .post_count)
	tmpDir="/tmp/e621downloader/pool$poolId"
	chunk=0

	# This ensure the directory exists and it contains only the meta json.
	rm -rf "$tmpDir" >/dev/null 2>&1
	mkdir -p "$tmpDir"
	mv "/tmp/e621downloader/$*.json" "$tmpDir/meta.json"

	# Echo the pool info.
	lnsay "" # Clean the previous message
	echo "Pool $poolId: $poolName"

	while [[ $postCount -gt $(($chunk *100)) ]]; do
		chunk=$(($chunk +1))
		chunkUrl="https://e621.net/posts.json?limit=100&page=$chunk&tags=pool%3A$poolId"

		lnsay "Downloading chunk [$chunk]"
		fetch $chunkUrl |jq -c '.posts[] | {id, file}' >$tmpDir/chunk$chunk.json
	done

	lnsay "" # Clean the previous message
	# echo ""
}

# getImages function. Download and convert the images for the given poolId.
function getImages() {
	# Common vars used in the function.
	tmpDir="/tmp/e621downloader/pool$*"
	poolId=$(cat "$tmpDir/meta.json" |jq -r .id)
	poolName=$(cat "$tmpDir/meta.json" |jq -r .name |tr "_" " ")
	postCount=$(cat "$tmpDir/meta.json" |jq -r .post_count)
	page=0
	chunk=0

	# Echo the pool info.
	lnsay "" # Clean the previous message
	echo "Pool $poolId: $poolName"

	basis="Downloading pool images..."
	while [ $postCount -gt $(($chunk *100)) ]; do
		chunk=$(($chunk +1))
		chunkFile="$tmpDir/chunk$chunk.json"

		while read post; do
			page=$(($page +1))
			postId=$(echo "$post" |jq -r '.id')
			postCache="/tmp/e621downloader/Cache/$postId.webp"

			lnsay "$basis [$page/$postCount] $postId:Queue"
			if [ -f "$postCache" ]; then
				continue
			fi

			postUrl=$(echo "$post" |jq -r '.file.url')
			if [[ "null" == "$postUrl" ]]; then
				lnsay "" # just to clean the line
				echo "https://e621.net/posts/$postId: Null url received." \
				tee -a "/tmp/e621downloader/failedDownloads.log"
				# echo "" # Just to put a new line.
				continue
			fi

			lnsay "$basis [$page/$postCount] $postId:Downloading"
			tmpFile="$tmpDir/$postId.blob"
			curl -o "$tmpFile" "$postUrl" >/dev/null 2>&1
		done <$chunkFile
	done

	lnsay "" # Clean the previous message
	# echo "" # Just to put a new line.
}

# convertImages function. self descrived.
function convertImages() {
	# Common vars used in the function.
	tmpDir="/tmp/e621downloader/pool$*"
	poolId=$(cat "$tmpDir/meta.json" |jq -r .id)
	poolName=$(cat "$tmpDir/meta.json" |jq -r .name |tr "_" " ")
	page=0

	# Echo the pool info.
	lnsay "" # Clean the previous message
	echo "Pool $poolId: $poolName"

	find "$tmpDir" -type f |grep -P '\.blob$' >"$tmpDir/blob.list"
	postCount=$(cat "$tmpDir/blob.list" |wc -l)
	for postFile in $(cat "$tmpDir/blob.list"); do
		filename=$(basename -- "$postFile")
		filename="${filename%.*}"
		page=$(($page +1))

		cwebp -q 100 "$postFile" -o "/tmp/e621downloader/Cache/$filename.webp" >/dev/null 2>&1
		lnsay "Converting downloaded images... [$page/$postCount]"
	done
	lnsay ""
}

# buildZip function. Self descrived.
function buildZip() {
	# Common vars used in the function.
	tmpDir="/tmp/e621downloader/pool$*"
	poolId=$(cat "$tmpDir/meta.json" |jq -r .id)
	poolName=$(cat "$tmpDir/meta.json" |jq -r .name |tr "_" " ")
	postCount=$(cat "$tmpDir/meta.json" |jq -r .post_count)
	poolDir=$(pwd)"/"$(echo "$poolName"|sed -e 's/[^0-9a-z., \-]/_/gi'| sed -e 's/\.$//g')
	page=0

	# Echo the pool info.
	lnsay "" # Clean the previous message
	echo "Pool $poolId: $poolName"

	# Create an empty file and put the meta.
	rm -rf "$poolDir" >/dev/null 2>&1
	mkdir -p "$poolDir"
	cp "$tmpDir/meta.json" "$poolDir/meta.json"

	basis="Packaging zip file..."
	for postId in $(cat "$tmpDir/meta.json" |jq -cr '.post_ids[]'); do
		post=$(echo "$post") # Just to be safe.
		page=$(($page +1))
		pagePadded=$(printf "%04d" $page)
		postId=$(echo "$postId") # Just to be safe.

		lnsay "$basis [$page/$postCount] Placing files"
		cp "/tmp/e621downloader/Cache/$postId.webp" "$poolDir/$pagePadded.webp" >/dev/null 2>&1
	done

	lnsay "$basis [-/-] Packaging 7z"
	rm -rf "$poolDir.zip" >/dev/null 2>&1
	7z a -tzip -sdel -mx7 "$poolDir.zip" "$poolDir" >/dev/null 2>&1
	lnsay ""
}

## Main app
mkdir -p "/tmp/e621downloader/Cache"

echo "e621 pool downloader - By Shelrock (A.k.a. Perritu / SystemRevolution)"
echo ""

if [ -f $(dirname "$0")"/.session" ]; then
	sessionCookie=$(cat $(dirname "$0")"/.session")
fi

if [[ "" == "$*" ]]; then
	echo "Usage: e621downloader poolId [poolId [poolId [...]]]"
	return
fi

echo "Build working directory."
for pool in $(echo $*); do buildMeta $pool; done
echo ""

echo "Downloading files."
for pool in $(echo $*); do getImages $pool; done
echo ""

echo "Converting files."
for pool in $(echo $*); do convertImages $pool; done
echo ""

echo "Generating zip files."
for pool in $(echo $*); do buildZip $pool; done
echo ""

echo "Cleaning temp files."
for pool in $(echo $*); do
	rm -rf "/tmp/e621downloader/pool$pool" >/dev/null 2>&1
done

if [ -f "/tmp/e621downloader/failedDownloads.log" ]; then
	echo "There was inaccesable files during downloads."
	echo "See \`/tmp/e621downloader/failedDownloads.log\` for more information."
	echo ""
	echo "To remove this message, remove or relocate the above log."
fi
