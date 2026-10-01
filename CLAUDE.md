# Working on SlopEngine

## Mortaro's inbox comes first

[`mortaros_notes.md`](mortaros_notes.md) is Mortaro's inbox. Read it at the start of every session and again before
starting a new piece of work. Every note in it is a request or a decision from Mortaro:

1. Act on it, or record it where it belongs: the rule on the docs page that teaches it, and where it came from in
   [`design/decisions.md`](design/decisions.md); [`design/INSIGHTS.md`](design/INSIGHTS.md); or a report to the Spite
   language session when it is about the language.
2. Then delete it from the inbox. Leave only the header and notes that are not handled yet.

Notes about the language itself go to `D:\Projects\SpiteLanguage\mortaros_notes.md`, which the language session
empties the same way.

## Where things live

- `docs/` is documentation for people using the engine, and nothing else. It holds no notes to AI agents, no
  implementation status ("not built", "yet", "known gap", "went from ... to ..."), no decision bookkeeping (no D
  numbers, no "Mortaro, date", no "a proposal by Claude"), and no alert numbers. Each page teaches the engine as it
  works and ends with a "Next:" link along the [reading order](docs/README.md#reading-order), which
  [`README.md`](README.md#documentation) lists too. A new page goes into both lists and into the chain of "Next:"
  links.
- `design/` is for the people and agents who build the engine:
  - [`design/status.md`](design/status.md): what the docs describe but is not built, or only in part, known gaps,
    and measurements over time, page by page;
  - [`design/decisions.md`](design/decisions.md): where each rule in the docs came from: Mortaro's decisions with
    their dates, the Spite decisions a rule rests on, game alerts, and proposals not confirmed yet;
  - [`design/roadmap.md`](design/roadmap.md): what is built next, and in what order;
  - [`design/INSIGHTS.md`](design/INSIGHTS.md): what building the engine taught us about Spite, and every bug
    reported upstream.

When you build something, delete its line from `design/status.md`. When you add something that is not built yet, the
docs page describes it only once it works; until then it lives in `design/`.

## What to read

- [`README.md`](README.md) and [`docs/`](docs/README.md), in the reading order: what exists and how to use it.
- [`docs/conventions.md`](docs/conventions.md): folders, naming, and the rules Spite's compiler enforces.
- [`design/`](design/), above, before changing anything it covers.

## How to work

- Compile and run from `examples/` with `D:/Projects/SpiteLanguage/bin/spite <example>`; see
  [`docs/testing.md`](docs/testing.md) for the test programs.
- Report compiler bugs and documentation that keeps causing mistakes to the "Language implementation review"
  session, with a priority based on whether SlopEngine uses the feature.
- Mortaro decides the API. Mark your own proposals as proposals in `design/decisions.md`, never in the docs.

## Writing

- **No em dashes, anywhere**: not the character, and not two hyphens between spaces standing in for one, in code,
  comments, docs or commit messages (command-line separators such as `spite program -- --flag` are fine). End the
  sentence, or use a colon, a comma or parentheses.
- **The engine never names the games built on it**, in docs, examples, comments or design notes, the way Spite never
  names its packages. Write "a game", and record what a game needed as the engine need it is.
- `bash scripts/check_writing.sh` checks both over every tracked file, and the `pre-commit` hook runs it.

## Commits

The same conventions as the Spite language repository. Start every message with one gitmoji, then a lowercase
imperative summary: ✨ feature · 🐛 bugfix · 📝 docs · ♻️ refactor · ✅ tests · 🔥 removal · ⚡ performance ·
🚨 lints · 🏗️ structure · 🔒 security · ⏪ revert. End it with the model that wrote it, named as the model you are
actually running as:

```
Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>
```

`scripts/hooks/commit-msg` rejects a message without that trailer or with an em dash, and `scripts/hooks/pre-commit`
runs the writing check; each clone runs `git config core.hooksPath scripts/hooks` once.
