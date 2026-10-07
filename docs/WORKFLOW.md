# User workflow

Use the original planning chat as the main point of contact. The seven task chats hold focused execution context; the user does not need to choose among them or copy messages between them.

## Starting

The user approves one task at a time in this main chat. Saying "approved" in response to the proposed next task authorizes the main chat to start that task in its existing task chat and send the follow-ups necessary to complete it. The user approved T01, then T02, then T03 on 2026-10-07.

Approval applies to the named next task, including its implementation, verification and relevant corrections. It does not authorize starting the following task. Do not create additional chats or background schedules without a user request.

## Coordination after authorization

1. Check actual environment readiness and current project/task state.
2. Select the next task with satisfied dependencies. Default order: T01, T02, T03, T04, T05, T06, T07.
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
