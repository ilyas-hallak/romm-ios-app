# Working agreements

This file applies to every task in this repository.

## Pull requests

Open every PR as a draft: `gh pr create --draft`.
It stays a draft until all three status gates below are checked.

### Body

The body starts with the status block, followed by a short description.

    ## Status
    - [ ] Code complete
    - [ ] Manually tested
    - [ ] Reviewed

    <two or three sentences on what changed and why>

Rules for the text:

- English, short, plain. Write it the way a person would, not as a report.
- No Problem/Root cause/Build status sections, no walls of bullets, no restating the diff.
- Never mention AI, Claude, or the tooling used. No `Co-Authored-By` trailers, no "Generated with" footers. The same goes for commit messages.
- Never include a link to an agent or session URL. Anyone who opens such a link can take over that session.
- No em dashes, use commas or plain hyphens.

### Status gates

- **Code complete** is checked by whoever opens the PR, once the code builds and the tests pass.
- **Manually tested** is checked by Ilyas only, after he tested on a real device. Never check this box for him.
- **Reviewed** is checked by the review run, once its findings are resolved.

When all three are checked, take the PR out of draft with `gh pr ready <number>`.

Note that `gh pr create --body` bypasses `.github/pull_request_template.md`, so the status block has to be part of the body you pass in.

## Code review

A review is its own step, started after the manual test, possibly from a different session.
Run it with `/pr-review`.

**Correctness first.**
Bugs outrank style. Report findings in that order, each with `file:line` and a concrete suggestion.

**Architecture**

- Clean Architecture layering holds: UI -> Domain -> Data, dependencies point inwards.
- Use cases never call other use cases. Composition happens in the caller, so in a view model or a service.
- Dependencies go through protocols, so the code stays testable.

**Clean code**

- Small methods with few parameters, small types, speaking names.
- KISS and SOLID as a guideline, not as dogma.
- Flag over engineering as well: unnecessary abstractions, premature generalisation, patterns too heavy for the problem at hand.
- No duplication worth removing, and consistent with the surrounding code.

**Comments**

- English, simple words, short.
- Only where the code cannot speak for itself, for example a non obvious reason or a workaround.
- Flag noisy comments: restating the code, section banners, commented out code, doc blocks on trivial members.

**Tests**

- Critical paths and real logic are covered, so use cases, parsing, state handling. No tests for trivia, no coverage target.
- New tests use Swift Testing, XCTest only in existing files.

## Delegating work

Token usage matters, so hand mechanical work to cheaper models instead of doing it inline.

- Haiku for mechanical edits with a clear spec, searches, renames, running builds and tests, collecting output.
- Sonnet for self contained implementation work and for the individual review dimensions.
- The main model keeps architecture decisions, the final review judgement, and anything where the call is not obvious.

A subagent does not see this conversation, so brief it with the full context it needs.
