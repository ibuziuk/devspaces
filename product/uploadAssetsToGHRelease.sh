#!/bin/bash
#
# Copyright (c) 2021 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# Contributors:
#   Red Hat, Inc. - initial API and implementation
#
# push locally built asset* files to github

set -e

# defaults
CSV_VERSION=2.y.0 # csv 2.y.0
PREFIX=""
fileList=""

MIDSTM_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "crw-2-rhel-8")
if [[ ${MIDSTM_BRANCH} != "crw-"*"-rhel-"* ]]; then MIDSTM_BRANCH="crw-2-rhel-8"; fi

usage () {
    echo "
Usage:   $0 -v [CRW CSV_VERSION] --prefix [unique prefix] file1.tar.gz file2.tar.gz
Example: $0 -v 2.y.0 --prefix crw-theia
"
    exit
}

if [[ $# -lt 1 ]]; then usage; fi

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-v') CSV_VERSION="$2"; shift 1;;
    '-b') MIDSTM_BRANCH="$2"; shift 1;;
    '-ght') GITHUB_TOKEN="$2"; shift 1;;
    '--prefix') PREFIX="$2"; shift 1;;
    '--help'|'-h') usage;;
    *) fileList="${fileList} $1";;
  esac
  shift 1
done

curlWithTokenPost()
{
  curl -sSL -XPOST -H "Authorization:token ${GITHUB_TOKEN}" "$1" "$2" "$3"
}

curlWithToken()
{
  curl -sSL -H "Authorization:token ${GITHUB_TOKEN}" "$1" "$2" "$3"
}

curlWithTokenBinary()
{
  curl -sSL --http1.1 -H "Authorization:token ${GITHUB_TOKEN}" -H "Content-Type:application/octet-stream" --data-binary "$1" "$2" "$3"
}

getId()
{
    ID=""
    loc_RELEASE_ID=$1
    loc_fileToPush=$2
    ID=$(curlWithToken -H "Accept: application/vnd.github.v3+json" https://api.github.com/repos/redhat-developer/codeready-workspaces-images/releases/${loc_RELEASE_ID}/assets | jq -r --arg fileToPush "${loc_fileToPush}" '.[] | select (.name=="'$loc_fileToPush'")|.id')
}

# check if existing release exists
releases_URL="https://api.github.com/repos/redhat-developer/codeready-workspaces-images/releases"
# shellcheck disable=2086
RELEASE_ID=$(curlWithToken -H "Accept: application/vnd.github.v3+json" $releases_URL | jq -r --arg CSV_VERSION "${CSV_VERSION}" '.[] | select(.name=="Assets for the '$CSV_VERSION' release")|.url' || true); RELEASE_ID=${RELEASE_ID##*/}
if [[ -z $RELEASE_ID ]]; then 
    curlWithTokenPost --data '{"tag_name": "'"${CSV_VERSION}"'", "target_commitish": "'"${MIDSTM_BRANCH}"'", "name": "Assets for the '"${CSV_VERSION}"' release", "body": "Container build asset files for '"${CSV_VERSION}"'", "draft": false, "prerelease": true}' $releases_URL > "/tmp/${CSV_VERSION}"
    # Extract the id of the release from the creation response
    RELEASE_ID="$(jq -r .id "/tmp/${CSV_VERSION}")"
fi

# upload artifacts for each platform 
for fileName in $fileList; do
    if [[ ${PREFIX} ]]; then 
        fileToPush="${PREFIX}-${fileName}"
    else 
        fileToPush="${fileName}"
    fi
    echo "Uploading new asset $fileToPush"
    # attempt to upload a new file
    if [[ $(curlWithTokenBinary @"${fileToPush}" -XPOST "https://uploads.github.com/repos/redhat-developer/codeready-workspaces-images/releases/${RELEASE_ID}/assets?name=${fileToPush}") ]]; then
        getId $RELEASE_ID $fileToPush
        echo "Uploaded new asset $ID to https://api.github.com/repos/redhat-developer/codeready-workspaces-images/releases/$RELEASE_ID/assets"
    else
        getId $RELEASE_ID $fileToPush
        if [[ $(curlWithToken @"${fileToPush}" -XPATCH "https://uploads.github.com/repos/redhat-developer/codeready-workspaces-images/releases/${RELEASE_ID}/assets/${ID}?name=${fileToPush}") ]]; then
                getId $RELEASE_ID $fileToPush
                echo "Updated asset $ID in https://api.github.com/repos/redhat-developer/codeready-workspaces-images/releases/$RELEASE_ID/assets/${ID}"
        else
            echo "ERROR: could not upload or update file $fileToPush to https://api.github.com/repos/redhat-developer/codeready-workspaces-images/releases/$RELEASE_ID/assets"
        fi
    fi
done
