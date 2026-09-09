# GitHub review widget

The work PR widget reads review-ticket metadata from Everything App alongside
the existing authored and requested-review queues.

Each requested-review row offers **Review** or **Re-review**. Both actions ask
the service to queue the agent on the same review ticket when one exists.
Queued and running reviews show **Reviewing** in place of the button; the
widget refreshes every five seconds while any review is active. **Ticket**
opens the linked item in Everything App. Completed agent reviews show
**Review ready** until the owner handles the ticket.

The agent prepares a private pending GitHub review for the owner to submit.
Re-reviewing refreshes the agent's pending comments or starts a new draft
after a prior review was submitted. The widget only calls Everything App's
review endpoint; it never submits a GitHub review.

Credentials remain in the desktop companion's local runtime configuration.
The helper validates the returned ticket and reports request failures without
printing the response body. Older API snapshots remain readable and show
**Review** until ticket metadata is available.

Run `python3 -m unittest discover -s tests -p 'test_github_review_widget.py' -v`
for the isolated API checks.
