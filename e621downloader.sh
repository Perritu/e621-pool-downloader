#!/bin/bash

## e621 pool downloader.

# fetch function. This runs a curl request with the proper user-agent.
function fetch() {
	curl -A "bash Curl; PoolDownloader/0.01 (by Shelrock); pd@angelgarcia.dev" -f $* 2>/dev/null
}

# lnsay function. Print a line and allow it to be overwriten. Intended to be used in loops.
function lnsay() {
	prf=$(echo "$*");
	cols=$(($(tput cols)-1))
	printf "\r\033[0K""${prf:0:$cols}"
}

# Function used to create the index (pair post ids with file urls)
function downloadImages() {
	lnsay "Quering pool $*"

	# Fetch the pool metadata. Also, doing a projection to discard irrelevant data.
	fetch "https://e621.net/pools/$*.json" |jq -c '{id, name, post_ids, post_count}' >/tmp/e621downloader/$*.json

	poolId=$(cat /tmp/e621downloader/$*.json |jq -r .id)
	poolName=$(cat /tmp/e621downloader/$*.json |jq -r .name |tr "_" " ")
	postCount=$(cat /tmp/e621downloader/$*.json |jq -r .post_count)

	lnsay "" # Just to clear the line.
	echo "PoolId: $poolId, $poolName"
	echo "Pages: $postCount"
	echo ""

	## Begin the fetch & download.
	# Var definitions.
	tmpDir="/tmp/e621downloader/pool$poolId"
	basis="Downloading files..."
	page=0
	chunk=0

	# Make sure the working directory is propertly organized.
	lnsay "$basis [Preparing working directory]"
	mkdir -p "$tmpDir"
	rm -rf "$tmpDir/*" 2>/dev/null
	mv /tmp/e621downloader/$*.json "$tmpDir/meta.json"

	while [ $postCount -gt $(($chunk *100)) ]; do
		# Vars of the round.
		chunk=$(($chunk +1))
		chunkUrl="https://e621.net/posts.json?limit=100&page=$chunk&tags=pool%3A$poolId"

		lnsay "$basis [Downloading chunk $chunk]"
		for post in $(fetch $chunkUrl |jq -c '.posts[] | {id, file}'); do
			page=$(($page +1))
			lnsay "$basis [$page/$postCount] Queue"

			postId=$(echo $post |jq -r '.id')
			postCache="/tmp/e621downloader/Cache/$postId.webp"

			if [ -f "$postCache" ]; then
				continue
			fi

			lnsay "$basis [$page/$postCount] Downloading"
			tpath="$tmpDir/tmp$postId."$(echo $post |jq -r '.file.ext')
			tpurl=$(echo $post |jq -r '.file.url')
			fetch -o "$tpath" $tpurl >/dev/null

			lnsay "$basis [$page/$postCount] Converting"
			cwebp -q 100 "$tpath" -o "$postCache" >/dev/null 2>&1
		done
		lnsay "$basis [$page/$postCount] Cleaning up"
		ls $tmpDir/tmp* 2>/dev/null |while read tmp; do rm $tmp; done
	done

	lnsay "$basis [Done!]"
	echo ""
}

#
function buildZip() {
	basis="Packaging zip..."
	baseDir=/tmp/e621downloader/pool$*

	poolName=$(cat "$baseDir/meta.json" |jq -r '.name' |tr "_" " " |sed -e 's/[^0-9a-z., \-]/_/gi')
	poolDir=$(echo $(pwd)/$poolName)

	postCount=$(cat "$baseDir/meta.json" |jq -r '.post_count')
	count=0

	echo "Pool $*: $poolName"
	echo ""

	# if [ -f "$poolDir" ]; then rm -rf "$poolDir"; fi
	if [[ $(ls "$poolDir" 2>/dev/null) ]]; then rm -rf "$poolDir"; fi
	mkdir -p "$poolDir"
	cp "$baseDir/meta.json" "$poolDir/meta.json"

	for post in $(cat "$poolDir/meta.json" |jq '.post_ids[]'); do
		post=$(echo $post)
		count=$(($count +1))
		padded=$(printf "%04d" $count)

		lnsay "$basis [$count/$postCount] Placing files"
		if [ -f "/tmp/e621downloader/Cache/$post.webp" ]; then
			cp "/tmp/e621downloader/Cache/$post.webp" "$poolDir/$padded.webp"
		fi
	done

	lnsay "$basis [-/-] Packaging 7z"
	if [[ $(ls "$poolName.zip" 2>/dev/null) ]]; then rm -rf "$poolName.zip"; fi
	7z a -tzip -sdel -mx7 "$poolName.zip" "$poolName" >/dev/null 2>&1
	# 7z a -tzip -sdel -mx7 "$zipname" "$foldername" >/dev/null 2>&1
}

## Main app
mkdir -p "/tmp/e621downloader/Cache"

echo "e621 pool downloader - By Shelrock (A.k.a. Perritu / SystemRevolution)"
echo ""

if [[ "" == "$*" ]]; then
	echo "Usage: e621downloader poolId [poolId [poolId [...]]]"
	exit
fi

for pool in $(echo $*); do downloadImages $pool; done
for pool in $(echo $*); do buildZip $pool; done
