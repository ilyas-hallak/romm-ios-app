---
description: Ship a new build to TestFlight from the permanent release worktree, with an auto-written changelog set in App Store Connect
argument-hint: [optional release notes — overrides the auto-generated ones]
---

Goal: "ship to TestFlight" in one shot, built from a clean, up-to-date `main`, with the
build's release notes ("What to Test") written from git and set in App Store Connect.

Run autonomously and pause for **exactly one confirmation**: approval of the changelog
before uploading. Everything else proceeds without asking.

## The release worktree is permanent

Builds always happen in `.worktrees/testflight-release`, a dedicated worktree that stays
around between releases. **Never remove it, never recreate it, never ask where to build.**
It keeps the initialized `Vendor/*` submodules, which is the slow part of a fresh checkout,
and it keeps the user's own work in the main checkout untouched.

It sits on a **detached HEAD** on purpose, so `main` stays available in the main checkout.

## 1. Refresh the worktree

```
git fetch origin
git -C .worktrees/testflight-release checkout --detach origin/main
git -C .worktrees/testflight-release submodule update --init --recursive
```

The checkout is expected to report modified `Vendor/*` entries. That is submodule pointer
drift, harmless, and unrelated to signing. Leave it alone.

This resets the worktree to `origin/main` on every run, so whatever it sat on before does
not matter. Print what it landed on and report it, so a stale fetch or a still-unmerged PR
becomes visible before a 20 minute upload:

```
git -C .worktrees/testflight-release log --oneline -1
```

If the user expected something that is not in that commit, stop and ask. Shipping the wrong
`main` costs a full build cycle.

If, and only if, the directory does not exist, create it once and copy in the gitignored
secrets, which a fresh checkout will not have:

```
git worktree add --detach .worktrees/testflight-release origin/main
cp romm/fastlane/.env .worktrees/testflight-release/romm/fastlane/.env
cp romm/fastlane/AuthKey_*.p8 .worktrees/testflight-release/romm/fastlane/
git -C .worktrees/testflight-release submodule update --init --recursive
```

Signing needs no manual intervention. The `beta` lane passes `-allowProvisioningUpdates`
with the API key and sets `teamID` in `export_options`, so the `DEVELOPMENT_TEAM` values
inside the vendored cores do not matter. If a build ever fails on signing, the cause is the
API key's role, not the submodules, see step 5.

All commands below run inside `.worktrees/testflight-release/romm`.

## 2. Find out what is actually new

Do not guess the range from `CURRENT_PROJECT_VERSION` or from `chore(release)` commits.
Both rot: the lane injects the build number via `xcargs` and never commits it.

```
FASTLANE_SKIP_UPDATE_CHECK=1 fastlane verify
```

This prints the latest build number already on TestFlight and doubles as an API key check.
The upload will be that number plus one.

For the commit range, prefer the tag the previous run left behind:

```
git describe --tags --abbrev=0 --match 'testflight/*'
```

If there is no such tag yet, say so in the changelog proposal and fall back to the last ~15
commits, flagging that the range is a guess.

## 3. Assemble the changelog

There are **two** changelog channels and they are easy to confuse. This step writes the
first one. Do not skip the second.

1. **App Store Connect "What to Test"** — the notes assembled below, passed via
   `TF_CHANGELOG`. Testers see this in the TestFlight app.
2. **`CHANGELOG.md` in the repo root** — feeds the in-app "What's New" screen and the
   update check, which fetch it from raw.githubusercontent on `main`. Nothing in this
   command writes it.

So before uploading, check that `CHANGELOG.md` on `origin/main` has an entry for the build
number `fastlane verify` just reported plus one:

```
git -C .worktrees/testflight-release grep -c "### Build <next-number>" HEAD -- CHANGELOG.md
```

If it is missing or still says `TODO`, stop and tell the user. The upload would otherwise
succeed while the app shows no release notes at all. The file's format is parsed, so a new
entry must copy the existing structure exactly: `### Build N (YYYY-MM-DD)`, then the
`**New**` / `**Fixed**` / `**Known issues**` sections. Offer to write it, then let the user
merge it to `main` before continuing, since the app reads `main`, not the local worktree.

- If the user passed text in `$ARGUMENTS`, use it verbatim and skip generation.
- Otherwise summarize the commits in the range into a few short, user-facing lines.
  Skip internal, CI and refactor noise. Merge related commits.
  - Tone: **English, casual and human**, like telling a friend what's new. No hashes, no
    conventional-commit prefixes, no "Merge branch…". No em-dashes, use commas.
  - Group under short headings when there is more than one theme.
  - Be honest about known limitations testers will hit, and check open issues for ones the
    release touches. Overselling a half-finished feature generates bogus reports.
- **Show the notes and get an explicit OK before uploading.** Let the user tweak the text.

## 4. Ship

Write the approved notes to a scratch file and pass them in, so quoting and newlines
survive. Run in the background, this takes 10 to 20 minutes: archive, upload, then waiting
for build processing so the notes can attach in ASC.

```
TF_CHANGELOG="$(cat <notes-file>)" FASTLANE_SKIP_UPDATE_CHECK=1 fastlane beta
```

The changelog goes on the command line, the credentials never do. Those come from
`romm/fastlane/.env`.

Use plain `fastlane`, not `bundle exec fastlane`. The system Ruby 2.6 cannot load the
Bundler version pinned in `Gemfile.lock`, the Homebrew fastlane works.

## 5. Report and tag

Confirm the uploaded build number and that the log says `Successfully set the changelog for
build`. Then leave a marker so the next run knows where the range starts:

```
git tag testflight/<build> <sha> && git push origin testflight/<build>
```

Leave the worktree in place.

On failure, surface the relevant fastlane error lines and stop, do not retry blindly.
`Unauthorized Access` on `verify` means the API key is wrong or lacks the Admin role that
cloud signing needs, not that the build is broken.
