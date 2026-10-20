# Issue tracker: GitHub

The issues and specs of this repo are GitHub issues in `gigosaurus/rs-production-planner`. Use the `gh` CLI for all operations.

## Conventions

- Each implementation issue is one GitHub issue. Never put all the tickets in one issue.
- A spec is an issue with the `spec` label.
- A triage label records the triage state. See `triage-labels.md` for the label strings.
- A `type:<type>` label records the ticket type: `type:research`, `type:prototype`, `type:grilling` or `type:task`.
- Comments and conversation history are GitHub issue comments.
- To refer to an issue, write `#N`.

## When a skill says "publish to the issue tracker"

Run `gh issue create --title "<title>" --body-file <file> --label <labels>`.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <N> --comments`. Usually the user gives the issue number.

## When you start work on an issue

1. Run `gh issue view <N> --json assignees`.
2. If the issue has no assignee, run `gh issue edit <N> --add-assignee @me`.
3. If a different person is the assignee, stop and ask the user.

Do this before you write code, make a branch or start a skill.

## Wayfinding operations

`/wayfinder` uses these operations. The **map** is an issue with one **child** sub-issue for each ticket.

- **Map**: an issue with the `map` label. Its body has Notes, Decisions-so-far and Fog.
- **Child ticket**: a sub-issue of the map. The body contains the question. A `type:<type>` label records the ticket type.
  - To add a sub-issue: `gh api repos/{owner}/{repo}/issues/<map>/sub_issues -f sub_issue_id=<child database id>`. Get the database id with `gh api repos/{owner}/{repo}/issues/<child> --jq .id`.
  - To list sub-issues: `gh api repos/{owner}/{repo}/issues/<map>/sub_issues`.
- **Blocking**: a `Blocked by: #N, #N` line at the top of the body. A ticket is unblocked when each issue in its list is closed.
- **Frontier**: find the sub-issues of the map that are open, unblocked and have no assignee. The lowest number goes first.
- **Claim**: see "When you start work on an issue".
- **Resolve**: add the answer as a comment that starts with `## Answer`. Close the issue. Then add a context pointer (a summary and `#N`) to Decisions-so-far in the map body.
