# PR Automation

Posts a Microsoft Teams message when a pull request is raised against `develop`.

## Branches
- `main` – production
- `develop` – integration; PRs target this branch
- `feature/*` – work branches, PR into `develop`

## Setup
Add repo secret `TEAMS_WEBHOOK_URL` (Settings → Secrets and variables → Actions). Never commit the URL.
