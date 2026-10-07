# User workflow

Use the original planning chat as the main point of contact. The seven task chats hold focused execution context; the user does not need to choose among them or copy messages between them.

## Starting

After the iOS simulator runtime download completes, the user can tell the main chat: "Xcode finished downloading. Manage the seven task chats and build the demo in order."

This explicitly authorizes the main chat to send implementation instructions and necessary follow-ups to the seven existing task chats for this demo. Until that instruction, do not infer permission to message another chat from a request merely to explain the workflow. Do not create additional chats or background schedules without a user request.

## Coordination after authorization

1. Check actual environment readiness and current project/task state.
2. Select the next task with satisfied dependencies. Default order: T01, T02, T03, T04, T05, T06, T07.
3. Start that task in its existing chat with current constraints and handoff context.
4. Follow progress using compact task-status waits while the main chat is actively working. Bring material preferences and missing inputs back to the user here.
5. Inspect the changes and acceptance evidence; completion in a chat is not sufficient proof of acceptance. Resolve relevant failures before dependent implementation.
6. Keep TASKS.md and PROGRESS.md current and continue to the next ready task within the authorized demo scope.

Default to one implementation task at a time in the shared checkout. Standalone design exploration can be separate, but multiple app-source writers must not run together.

The main chat should not promise ongoing background monitoring after its turn ends without an explicitly requested automation. If work has stopped, the user can say "Continue" here; the main chat checks state rather than making the user identify a task.

## User input

Give design preferences, receipt-folder locations, corrections and demo feedback in the main chat. Task-chat replies are optional unless the app requires a permission/input interaction in that chat. Never ask the user to manually synchronize planning files or task summaries.

## Review points

- Environment and on-device AI readiness.
- Wallet concept selection before production interface implementation.
- Extraction evaluation and any private real-receipt dataset required.
- Imported-image demo walkthrough.
- Split/search demo before physical iPhone camera work.
