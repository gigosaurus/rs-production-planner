#!/usr/bin/env bash
# This script checks each plugin.json file.
# Each file must be valid JSON.
# requiredDependencies and optionalDependencies must be objects. The game client rejects arrays.
set -u
status=0
while IFS= read -r file; do
    if ! jq -e '
        [.requiredDependencies, .optionalDependencies]
        | all(. == null or type == "object")
    ' "$file" >/dev/null; then
        echo "FAIL $file: file is not valid JSON, or a dependency field is not an object"
        status=1
    fi
done < <(git ls-files '*plugin.json')
exit $status
