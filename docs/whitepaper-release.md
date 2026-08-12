# Releasing the Whitepaper

The whitepaper is a Typst document in `whitepaper/`. The compiled PDF is
gitignored — it exists only as a CI artifact or a release asset, never in the
repo. Releases are cut by pushing a `whitepaper/v*` tag; CI builds the PDF and
publishes the GitHub release.

## Versioning

The version lives in exactly one place — `whitepaper/main.typ`:

```typst
#let version = "v0.2.0"
```

It renders onto the title page and the release workflow greps for it. **A tag
whose version does not match this line fails the build.** That is deliberate: it
makes it impossible to ship a PDF whose cover says one version while the release
says another.

Use semver-ish judgement: patch for typos and clarifications, minor for new or
substantially rewritten chapters, major for a restructure or a v1.0 declaration.

## Cutting a release

**1. Bump the version and write the notes, in the PR that changes the content.**

Edit `#let version` in `whitepaper/main.typ`, and add
`whitepaper/releases/<version>.md` with the release notes. Both get reviewed
alongside the prose. The notes file becomes the release body verbatim — write it
for a reader who has not seen the diff. (If the file is missing at tag time, CI
falls back to auto-generated commit-list notes and logs a warning.)

**2. Merge the PR.**

`.github/workflows/pr.yml` builds the PDF on any PR touching `whitepaper/**` and
uploads it as a `whitepaper` artifact — download it from the checks tab to
proofread the rendered output before merging.

**3. Tag the merge commit and push.**

```bash
git checkout main && git pull
git tag -a whitepaper/v0.2.0 -m "Whitepaper v0.2.0"
git push origin whitepaper/v0.2.0
```

The `whitepaper/` prefix matters — it is what triggers the workflow, and it keeps
whitepaper versions in their own namespace, separate from any future protocol
tags.

**4. CI does the rest.**

`.github/workflows/whitepaper-release.yml` verifies the version, compiles the
PDF, and publishes a release named `Whitepaper whitepaper/v0.2.0` with
`armature-whitepaper.pdf` attached. Asset name is stable across releases, so
`releases/latest` links keep working.

## If the version check fails

The tag and `main.typ` disagree. Fix `main.typ` on `main`, then move the tag:

```bash
git tag -d whitepaper/v0.2.0
git push origin :refs/tags/whitepaper/v0.2.0
# re-tag the corrected commit and push again
```

## Building locally

```bash
make dev-docs     # watch and recompile to whitepaper/main.pdf
make build-docs   # one-shot build to whitepaper/dist/armature-whitepaper.pdf
```

Requires Typst: `brew install typst` (or see typst.app/docs).

## Linking to the whitepaper

Link to `releases/latest` rather than a pinned tag, so the link survives the next
release:

<https://github.com/loash-industries/armature/releases/latest>
