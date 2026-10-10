# User workflow

Use the original planning chat as the main point of contact. Seven Phase 1 task chats were archived on 2026-10-09; their implementation evidence remains in the repository. Five Phase 2 chats are prepared in the “Sliplet · Phase 2” sidebar section, with Main first. The user does not need to choose among them or copy messages between them.

## Starting

The user approves one task at a time in this main chat. Saying "approved" in response to the proposed next task authorizes the main chat to start that task in its existing task chat and send the follow-ups necessary to complete it. The user approved T01, then T02, then T03, then T04, then T05 on 2026-10-07.

Approval applies to the named next task, including its implementation, verification and relevant corrections. It does not authorize starting the following task. Do not create additional chats or background schedules without a user request.

## Coordination after authorization

1. Check actual environment readiness and current project/task state.
2. Select the next task with satisfied dependencies. Current order: P2-01 recognition audit, P2-02 capture/layout, P2-03 retailer parsing, P2-04 faster corrections, then P2-05 personal release readiness. Each begins only after its dependencies are accepted and its own approval is given.
3. Start that task in its existing chat with current constraints and handoff context.
4. Follow progress using compact task-status waits while the main chat is actively working. Bring material preferences and missing inputs back to the user here.
5. Inspect the changes and acceptance evidence; completion in a chat is not sufficient proof of acceptance. Resolve relevant failures before dependent implementation.
6. Keep TASKS.md and PROGRESS.md current. Commit and push verified task changes to the existing GitHub repository using the configured SSH signing identity; preserve existing history and avoid committing unrelated work.
7. Report what the completed task delivered, current milestone, actual commit message/hash and push status, and the proposed next task. Ask for approval and stop before dispatching that next task.

Default to one implementation task at a time in the shared checkout. Standalone design exploration can be separate, but multiple app-source writers must not run together.

The main chat should not promise ongoing background monitoring after its turn ends without an explicitly requested automation. If an approved task is interrupted, the user can say "Continue" here to resume it. Starting a new task requires the next approval; the user does not need to identify or visit its execution chat.

## Required completion report

- Completed task: what changed and how acceptance was verified; material limitations if any.
- Current milestone: milestone name and status.
- Commit: actual message, hash and whether it was pushed.
- Next task: task ID/title, goal and any unmet prerequisites.
- Approval question: ask whether to start the proposed next task; wait for the user's answer.

## User input

Give design preferences, receipt-folder locations, corrections and demo feedback in the main chat. Task-chat replies are optional unless the app requires a permission/input interaction in that chat. Never ask the user to manually synchronize planning files or task summaries.

## Review points

- Environment and on-device AI readiness.
- Wallet concept selection before production interface implementation.
- Extraction evaluation and any private real-receipt dataset required.
- Imported-image demo walkthrough.
- Split/search demo before physical iPhone camera work.

## Phase 2 preparation

The user requested the old-task cleanup and five corresponding Phase 2 chats on 2026-10-09. These chats have only read the roadmap/workflow and acknowledged their pending status; this request does not start the recognition audit. Detailed scopes, acceptance criteria and chat identities are in TASKS.md. The actual repository is /Users/moby/Desktop/cs/Sliplet, even if the saved desktop project still displays its former RcpLens name/path. Always use the actual path for repository work.

## Current handoff · 2026-10-09

P2-01 through P2-05 implementations have been individually approved and accepted in Main. P2-05 adds password-encrypted portable backups and merge-only restore. Next is the guided personal v0.2 iPhone walkthrough, requiring separate user approval; stay in Main. Follow [personal release protocol](PERSONAL_RELEASE.md). Real accuracy, human correction time and phone acceptance remain open.
