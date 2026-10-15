# Merge Queue Bot

Merge several GitLab merge requests together after testing their combined changes. Built with Dart, SQLite, and YAML configuration. Currently supports GitLab only.

## How it works

1. Assign ready, non-draft MRs to the bot.
2. The bot collects them in assignment order and creates a batch MR with one squash commit per original MR.
3. It waits for pipelines, then fast-forwards the successful batch into the target branch.
4. Original MRs are closed with a link to the merged batch. Their source branches are kept.

**No pipeline means merge without CI.** By default, the bot waits 10 seconds after publishing the batch to discover pipelines. It waits for every discovered pipeline to succeed; pipelines appearing later are ignored. Change this window with `pipeline_discovery_seconds`.

Changes to the target branch or an included MR cause the batch to be rebuilt. The bot does not check approvals; GitLab's own merge rules still apply.

## Get started

You need **Docker** and a GitLab service account token with `api` and `write_repository` scopes. The account must be able to push queue branches, manage MRs, and merge into the target branch.

### 1. Prepare GitLab

For each managed project:

- Choose **Fast-forward merge** and make squashing optional or disabled.
- Disable **automatic rebase** and **merged-results pipelines**.
- Protect target branches and disable force-pushes to them.
- Allow the bot to create and force-push `merge-queue/*` branches.
- Configure CI to run on branch pushes or MR creation. The bot never triggers pipelines itself.

GitLab can still block a batch because of approvals, unresolved discussions, or other merge rules. If pipelines are mandatory, GitLab will refuse a batch with no pipeline.

### 2. Configure and run

Create `config.yaml`:

```yaml
gitlab_url: https://gitlab.example.com
database: /data/queue.sqlite
work_directory: /data/repositories
projects:
  - id: group/project
    target_branches: [main]
```

Replace the URL, project, and target branch with yours. Create `.env` containing your token:

```dotenv
GITLAB_TOKEN=your-service-account-token
```

Run the release image from GitHub Container Registry. Replace `your-org/your-repository` with this repository's lowercase GitHub path; use a version tag to pin a release.

```sh
BOT_IMAGE=ghcr.io/your-org/your-repository:latest
docker pull "$BOT_IMAGE"
docker volume create merge-queue-data
docker run -d --name merge-queue-bot --restart unless-stopped \
  --env-file .env \
  --mount type=volume,src=merge-queue-data,dst=/data \
  --mount type=bind,src="$PWD/config.yaml",dst=/config/config.yaml,readonly \
  "$BOT_IMAGE"
```

View logs with `docker logs -f merge-queue-bot`. The volume preserves queue state across restarts; run only one instance for each managed queue. When using a bind mount for `/data`, give container UID **10001** write access.

See [config.example.yaml](config.example.yaml) for all settings. Defaults: poll every **30 seconds**, collect for **30 seconds**, batch up to **10 MRs**, and time out after **60 minutes**.

## When something fails

- **Failed pipeline:** the bot tests smaller groups, merges healthy ones, and returns failing MRs to their previous assignees when known.
- **Conflict or missing source branch:** fix the problem described in the MR comment, then reassign the bot.
- **Canceled/skipped pipeline, timeout, or blocked merge:** read the batch MR comment, resolve the problem, then run `docker restart merge-queue-bot` to retry.

The bot resumes unfinished work after a restart. If an original MR changes after its earlier version lands, it stays open and is returned to its assignees; reassign it when the remaining changes are ready. Rebasing onto the landed batch may be necessary to resolve squash-related conflicts.

