# Claude Code Instructions for pg_count_nulls

## GitHub CI

After **every** push, monitor GitHub CI to completion (`gh pr checks <pr> --watch` when the
branch has an open PR, `gh run watch` for a branch with no PR yet) — do not consider a push
complete until its CI run is green (or a failure is understood and explicitly accepted by
the user).

This includes the `claude-code-review` job specifically: a green job conclusion only means
the review *ran*, not that its findings were addressed. After the job completes, fetch and
read its actual PR comment (`gh api repos/<owner>/<repo>/issues/comments/<id>` from the
comment URL, or `gh pr view --json comments`) for open findings. A finding repeating across
several pushes with no corresponding fix commit is a signal being missed, not something to
let ride because the check itself is green.

Do not blindly implement review findings. They're generally good, but treat each one as a
claim to verify against the actual code before acting on it — the review re-reads the diff
each run without the code's full history or design intent in mind, and can be wrong or miss
context. When a finding's validity is unclear, or fixing it would touch design intent rather
than a mechanical mistake, ask before implementing rather than guessing.
