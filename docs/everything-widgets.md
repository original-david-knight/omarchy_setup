# Everything App bar widgets

The widgets read their service URL and desktop token from the local
`~/.config/everything-agent/config.json` deployed by private setup. Tests use
synthetic responses and temporary configuration; no account data is stored
in this repository.

## Assign to an agent

Tasks, Jira issues, and both GitHub PR lists offer **Assign**. It opens a
shared form where you choose a project and an agent. An existing task's
project is selected automatically; a new source task uses the service's
configured destination when available. Only active projects with a repository
and enabled agents with available capacity appear as choices.

For Jira, the agent implements the issue in the selected project. For a PR,
the agent reviews it and returns the review to you. Assignment keeps the
linked task rather than creating another copy.

Opening or cancelling the form only reads data. **Assign** submits the chosen
project, agent, and preview revision to `/api/delegation`, then refreshes the
list. A conflict keeps the form open and requires **Reload options** before
another attempt. Work already running with an agent cannot be reassigned.

The shared form and `delegate` helper live in `david.tasks`; deploy the three
widgets together with `stow_all.sh --bar-only`. The helper supports
`delegate preview SOURCE KEY` and
`delegate assign SOURCE KEY PROJECT_ID AGENT REVISION`, where `SOURCE` is
`task`, `jira`, or `github`.

## Tasks

The task endpoint now includes personal tasks, coding tickets, and completed
history. The widget preserves the service's `view`, `can_complete`,
`next_action`, project, and revision fields.

- **Needs you** shows personal tasks and work requiring an answer or review.
- **Waiting** shows work currently with an agent.
- **Completed** keeps finished and cancelled work accessible.
- A personal task opens in Tasks. Its inline button finishes it, or reopens
  it from Completed. The write sends an explicit `done` value and the
  displayed `X-Base-Revision`; a conflict refreshes the list and asks for a
  new click instead of retrying a stale write.
- Coding tickets open their project-item detail page for review, approval,
  or other workflow actions. They never receive a personal-task completion
  checkbox.

The `complete` helper retains its one-argument completion form and also
accepts `complete TASK_ID true|false REVISION` for the bar's guarded writes.
The list refreshes on opening, after a write, and every five minutes.

## Jira

The widget preserves the service's issue order and linked `task` state.
Each row has a **Task checkbox**: checked means a linked task exists,
including a completed task. Checking an empty box calls `POST /api/jira/task`
with only the issue key. Everything App creates or restores its one linked
task and chooses its project using the configured destination. The helper
requires a confirmed open task for that issue before reporting success.

Unchecking reads the linked task's current revision, then sends
`DELETE /api/tasks/{id}` with `X-Base-Revision`. A concurrent change refuses
the deletion and refreshes the panel. Deletion is recoverable: checking
again restores the task, and normal Jira polling respects a deleted task.
The checkbox changes only after the service confirms its state on refresh.
Use `task ISSUE_KEY` to create/restore or `task ISSUE_KEY delete TASK_ID` to
delete the linked task.

Clicking the issue title still opens Jira in the work browser profile.
Completing or reopening a task uses Everything App's task lifecycle; the
widgets do not implement their own Jira closure or synchronization rules.

## GitHub and listening

The GitHub widget retains the `mine` and `review` queues. Podcast queue,
subscription artwork, playback progress, and Spotify playlist formats remain
compatible with the existing listening widget.

## Verify and install

```sh
python3 -m unittest discover -s tests -p 'test_tasks.py'
python3 -m unittest discover -s tests -p 'test_widget_apis.py'
python3 -m unittest discover -s tests -p 'test_widget_assignment.py'
python3 -m unittest discover -s tests -p 'test_listening.py'
omarchy plugin validate omarchy/.config/omarchy/plugins/david.tasks
omarchy plugin validate omarchy/.config/omarchy/plugins/david.jira-work
omarchy plugin validate omarchy/.config/omarchy/plugins/david.github-work
./stow_all.sh --bar-only
omarchy-shell shell rescanPlugins
```

The tests start loopback HTTP fixtures. Stow installs any new helper links;
the assignment tests also exercise the native form in an isolated, offscreen
Quickshell instance when Omarchy Shell is installed.
editing the existing linked QML files normally reloads the widgets on save.
If the shell retains an older cached panel, run `omarchy restart shell`.
