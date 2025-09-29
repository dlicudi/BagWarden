#!/bin/bash

# Update Version Script for BagWarden
# Usage:
#   ./update_version.sh            # shows current version, latest tag, and pending commits
#   ./update_version.sh 1.6.0      # bumps version, commits, tags, and pushes

set -euo pipefail

TOC_FILE="BagWarden.toc"

if [[ ! -f "$TOC_FILE" ]]; then
    echo "Error: $TOC_FILE not found. Run this script from the repository root." >&2
    exit 1
fi

get_current_version() {
    local version_line
    version_line=$(grep '^## Version:' "$TOC_FILE" || true)
    if [[ -z $version_line ]]; then
        echo "Error: Could not find version line in $TOC_FILE" >&2
        exit 1
    fi
    echo "${version_line#### Version: }"
}

show_status() {
    local current_version
    current_version=$(get_current_version)
    echo "Current version: $current_version"

    local latest_tag
    latest_tag=$(git tag --list 'v*' --sort=-v:refname | head -n 1)
    if [[ -n $latest_tag ]]; then
        echo "Latest tag: $latest_tag"
        echo
        echo "Commits since $latest_tag:"
        git log --oneline "${latest_tag}..HEAD"
    else
        echo "No tags found."
    fi
}

update_version() {
    local new_version=$1

    if [[ ! $new_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Version must be in the form x.y.z (e.g., 1.6.0)" >&2
        exit 1
    fi

    echo "Updating version to $new_version..."

    # macOS/BSD sed needs the empty string after -i
    sed -i '' "s/^## Version: .*/## Version: $new_version/" "$TOC_FILE"

    git add "$TOC_FILE"
    git commit -m "Bump version to $new_version"
    git tag -a "v$new_version" -m "Version $new_version"
    git push
    git push origin "v$new_version"

    echo "Tagged and pushed v$new_version."
}

if [[ $# -eq 0 ]]; then
    show_status
else
    update_version "$1"
fi

