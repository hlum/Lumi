#!/bin/sh
# On a failed test run, post the failure summary to the PR so it can be read without App Store Connect.
# Needs the secret Xcode Cloud env var GITHUB_TOKEN (fine-grained PAT: Pull requests + Issues write on this repo).
[ "$CI_XCODEBUILD_EXIT_CODE" = "0" ] && exit 0
[ -z "$GITHUB_TOKEN" ] || [ -z "$CI_PULL_REQUEST_NUMBER" ] || [ -z "$CI_RESULT_BUNDLE_PATH" ] && exit 0

summary=$(xcrun xcresulttool get test-results summary --path "$CI_RESULT_BUNDLE_PATH" 2>&1 | head -c 50000)
body=$(printf 'Xcode Cloud: test action failed (build %s, exit %s)\n\n```json\n%s\n```' "$CI_BUILD_NUMBER" "$CI_XCODEBUILD_EXIT_CODE" "$summary")

printf '%s' "$body" | python3 -c 'import json,sys; print(json.dumps({"body": sys.stdin.read()}))' > /tmp/comment.json
curl -sS -X POST \
  -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  -d @/tmp/comment.json \
  "https://api.github.com/repos/hlum/Lumi/issues/$CI_PULL_REQUEST_NUMBER/comments" > /dev/null
exit 0
