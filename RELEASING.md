# Releasing

This repo uses **semantic-release** to publish GitHub Releases and maintain `CHANGELOG.md`.

## Versioning policy

- We use **SemVer** via Conventional Commits (`feat` → minor, `fix` → patch, `!` → major).
- While the major version is `0`, we still *try* to follow SemVer, but breaking changes can
  land in minor releases as the target is still stabilizing.
- Compatibility target: **Haxe 4.3.7** (see `README.md:1`).

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

## Publishing to Haxelib (manual for now)

`semantic-release` currently publishes GitHub Releases only. If you want to publish a matching
release to **Haxelib**, do this after the GitHub Release exists:

1) Ensure you are logged into haxelib:

```bash
haxelib setup
haxelib login
```

2) Build a Haxelib zip:

```bash
bash scripts/release/build-haxelib-zip.sh
```

3) Submit the zip:

```bash
haxelib submit dist/reflaxe.ocaml-<version>.zip
```

Notes:

- The zip is built from the current working tree. Run it from a clean checkout of the tag
  you intend to publish (e.g. `git checkout v0.9.0`).
- Long-term we may automate this as part of the Release workflow once credentials/secrets
  are set up appropriately.
