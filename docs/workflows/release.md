# Release Workflow

Hareeg Table uses Release Please for alpha versioning, changelog updates,
GitHub prereleases, and release APK uploads.

## What Runs Automatically

On every push to `main`, the `Release Please` workflow runs.

If there are releasable Conventional Commits since the last release, Release
Please opens or updates a release pull request. That PR contains:

- a `pubspec.yaml` version bump
- `.release-please-manifest.json` version tracking
- `CHANGELOG.md` release notes

When the release pull request is merged, the same workflow:

1. creates the version tag
2. creates the GitHub prerelease
3. checks out the release tag
4. builds the Android release APK
5. uploads the APK to the GitHub Release

No manual tag push is required.

The release APK is signed with a release keystore from GitHub Actions secrets.
Configure these repository secrets before merging a Release Please PR that should
publish an APK:

- `ANDROID_RELEASE_KEYSTORE_BASE64`: base64-encoded Android keystore file
- `ANDROID_RELEASE_KEYSTORE_PASSWORD`
- `ANDROID_RELEASE_KEY_ALIAS`
- `ANDROID_RELEASE_KEY_PASSWORD`

## What Maintainers Do

To make a specific implementation PR eligible for the next release:

1. Use Conventional Commit messages in the PR commits.
2. Include at least one releasable commit:
   - `feat:` for a minor release
   - `fix:` for a patch release
   - `feat!:` or `fix!:` for a major release
3. Merge the implementation PR into `main`.
4. Wait for Release Please to open or update the release PR.
5. Review the generated version, changelog, and release notes.
6. Merge the release PR when ready to publish.

Non-releasable commits such as `docs:`, `test:`, `chore:`, `ci:`, and `refactor:`
do not publish a release by themselves.

## First Alpha Release Trigger

The release automation setup PR intentionally includes a releasable commit with
this footer:

```text
Release-As: 1.0.0-alpha.1
```

That footer is the explicit trigger for the first alpha release version. After
that PR merges, Release Please opens the first release PR for `v1.0.0-alpha.1`.
Merging that generated release PR publishes the GitHub prerelease and uploads the
APK.

## Forcing A Specific Version

If a release must use a specific version, add a commit with a `Release-As`
footer before merging the implementation PR.

Example:

```text
chore: release 1.1.0

Release-As: 1.1.0
```

Release Please will use that version for the next release PR.

## APK Artifacts Versus Releases

`Android APK Artifact` still runs on pushes to `main`. It uploads a temporary
Actions artifact for verification and debugging. Those artifacts expire.

Permanent user-facing APKs are attached only to GitHub Releases created by the
`Release Please` workflow.

## First Run

The release manifest is bootstrapped at version `0.0.0`, and the config uses the
current merged `main` commit as the bootstrap SHA. That keeps the first generated
release PR focused on the release automation PR instead of the entire historical
project setup, while allowing the first alpha to be explicitly forced to
`1.0.0-alpha.1`.
