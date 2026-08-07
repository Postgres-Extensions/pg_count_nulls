# Claude Code Instructions for pg_count_nulls

## GitHub CI

After **every** push, monitor GitHub CI to completion (`gh pr checks <pr> --watch` when the
branch has an open PR, `gh run watch` for a branch with no PR yet) — do not consider a push
complete until its CI run is green (or a failure is understood and explicitly accepted by
the user).

This includes the `claude-code-review` job specifically: a green job conclusion only means
the review *ran*, not that its findings were addressed. After the job completes, fetch and
read its actual PR comment (`gh api repos/<owner>/<repo>/issues/comments/<id>` from the
comment URL, or `gh pr view --json comments`) for open findings.

For every finding, as soon as you see it: either act on it (fix it, or explicitly state why
it doesn't need fixing) or ask the user for direction. Never leave a finding unaddressed and
unacknowledged just because the check itself is green.

If a finding — or one remotely similar to a finding from an earlier push on the same PR —
shows up again, STOP immediately and ask the user for help before doing anything else. A
recurrence means you and the review bot are not in alignment (either the earlier fix didn't
actually address it, or you and the reviewer disagree about it), and continuing to guess at
it burns tokens without resolving the actual disagreement.

Do not blindly implement review findings, either. They're generally good, but treat each one
as a claim to verify against the actual code before acting on it — the review re-reads the
diff each run without the code's full history or design intent in mind, and can be wrong or
miss context.
