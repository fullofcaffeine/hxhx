# Releasing

This repo uses **semantic-release** to publish GitHub Releases and maintain `CHANGELOG.md`.

## How releases are created

- CI runs on push/PR.
- After CI succeeds on `master`/`main`, the Release workflow runs `semantic-release`.
- `semantic-release` decides the next semver version from commit history and then:
  - updates `CHANGELOG.md`,
  - syncs versions across `package.json`, `package-lock.json`, `haxelib.json`, and `haxe_libraries/reflaxe.ocaml.hxml`,
  - creates a release commit (`chore(release): x.y.z [skip ci]`),
  - tags the release (`vx.y.z`) and publishes a GitHub Release.

## Commit message conventions

Use Conventional Commits so semantic-release can determine the correct semver bump:

- `feat: ...` → minor
- `fix: ...` → patch
- `feat!: ...` / `fix!: ...` → major (breaking change)

If you use non-conventional commit messages, semantic-release will not publish a new release.

