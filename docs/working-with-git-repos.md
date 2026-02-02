Working with Github repositories



By Roger Watkins

1 min

42

thumbs up
1
Creating a new repository
Dealing with PRs and linear commit history
Creating a new repository
Setting up a new repository

Ensure the guidance in the team-manual is followed

Then set up the repo configuration using our template repo https://github.com/govuk-one-login/ct-aws-sample-pipelineConnect your Github account  as a guide

Repo settings 

Rule sets

Github actions / workflows (for terraform)

See 
GitHub Actions and Workflows 

Dependabot

PR template (actual template bespoke to each repository)

CODEOWNERS (actual config bespoke to each repository)

Pre-commit (for terraform)

Git ignore (for terraform - warning incomplete)

Dealing with PRs and linear commit history
A linear commit history is highly desirable because it avoids messy merge commits in the main branch history. It also enforces that working branches are up to date with main before they are merged - this avoids unexpected merge commit changes making their way into main that are not visible (or tested) in the PR.

When require branches to be up to date before merging is enabled, github will insist that you update the working branch inline with main before it can be merged. We want to avoid using merge commits to update working branches as again it results in a messy commit, unrelated changes and conflicts and also makes the code harder to unpick in main if the PR is merged. 

The tradeoff with these options enabled is that if we rebase branch through the UI - then commits that are signed with a gpg or ssh key effectively become unverified because github rewrites the branch history (and it’s commits) but doesn’t have the original key to do so (and cannot use it’s own private key either).

Every time another PR is merged and main is updated, then working branches will become out of date and require a local rebase.