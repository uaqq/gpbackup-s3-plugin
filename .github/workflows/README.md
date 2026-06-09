# CI Workflow

Builds and tests `gpbackup-s3-plugin` inside a Docker container for Ubuntu 22.04 and 24.04.

## Actual version

- `.github/workflows/ci.yml`

## What it does

1. **Build Docker image** — builds `ci/Dockerfile.ubuntu` with the target OS version;
   runs unit tests and packages the `.deb` inside the container
2. **Extract artifacts** — copies `deb-packages/` and `bin/` from the container
3. **Upload artifacts** — uploads deb packages and binaries as GitHub Actions artifacts

## Artifacts

Name                                      | Contents
----------------------------------------- | --------
`gpbackup-s3-plugin-deb-ubuntu<version>`  | `.deb`, `.ddeb`, `.build`, `.buildinfo`, `.changes`
`gpbackup-s3-plugin-bin-ubuntu<version>`  | `gpbackup_s3_plugin` binary

## Triggers

Event          | Branches / refs
-------------- | ---------------
`push`         | `master`, tags
`pull_request` | all branches
