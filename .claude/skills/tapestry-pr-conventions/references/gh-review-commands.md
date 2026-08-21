# Exact commands for working with PR review comments

All verified working against a real PR
([asteasolutions/tapestry-project#96](https://github.com/asteasolutions/tapestry-project/pull/96))
during this skill's own creation. `<owner>`/`<repo>`/`<number>` below — substitute the
real values; the examples use `asteasolutions`/`tapestry-project`/`96`.

## List every review and its inline comments

Reviews (the top-level "approved"/"commented"/"changes requested" events):

```bash
gh api repos/<owner>/<repo>/pulls/<number>/reviews
```

Every inline (line-level) comment, across all reviews, with the review it belongs to:

```bash
gh api repos/<owner>/<repo>/pulls/<number>/comments --paginate | python3 -c "
import json, sys
comments = json.load(sys.stdin)
for c in comments:
    print('='*80)
    print('review_id:', c.get('pull_request_review_id'))
    print('path:', c.get('path'), 'line:', c.get('line') or c.get('original_line'))
    print('body:', c.get('body'))
    print('in_reply_to_id:', c.get('in_reply_to_id'))
    print('created_at:', c.get('created_at'))
"
```

Filter to one review round by `pull_request_review_id` (from the reviews call above) once
you know which round you're responding to.

## Reply to a specific inline comment

Requires that comment's numeric `id` (the `id` field from the comments listing above, not
the review id):

```bash
gh api repos/<owner>/<repo>/pulls/<number>/comments/<comment_id>/replies \
  -f body="Fixed — <what changed>. See <commit-sha>."
```

This posts a genuine threaded reply visible under that specific comment, not just a
general PR comment — reviewers expect a reply on the thread itself, not a summary comment
elsewhere on the PR.

## Resolve a review thread (GraphQL only — no REST equivalent)

First, get the thread IDs (`PRRT_...`, not the same as a comment's numeric `id`) and
current resolved state:

```bash
gh api graphql -f query='
query {
  repository(owner: "<owner>", name: "<repo>") {
    pullRequest(number: <number>) {
      reviewThreads(first: 50) {
        nodes {
          id
          isResolved
          comments(first: 1) { nodes { databaseId body } }
        }
      }
    }
  }
}'
```

`comments.nodes[0].databaseId` matches the `id` from the REST comments listing above, so
you can match a thread back to the specific comment you replied to. Then resolve it:

```bash
gh api graphql -f query='
mutation($id: ID!) {
  resolveReviewThread(input: {threadId: $id}) {
    thread { isResolved }
  }
}' -f id="<thread-id>"
```

**Reply before resolving, not instead of** — a resolved thread with no reply reads as
"ignored," not "addressed," even if the code change is real. Only resolve a thread once
you've actually made the change (or explained why not) in a reply on that thread.

## Check overall PR state before assuming review status

```bash
gh pr view <number> --repo <owner>/<repo> --json state,mergeable,reviewDecision
```

`reviewDecision: "REVIEW_REQUIRED"` means no reviewer has approved yet — addressing every
comment doesn't by itself change this; a reviewer still has to re-approve.
