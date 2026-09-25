# Working on SlopEngine

## Mortaro's inbox comes first

[`mortaros_notes.md`](mortaros_notes.md) is Mortaro's inbox. Read it at the start of every session and again before
starting a new piece of work. Every note in it is a request or a decision from Mortaro:

1. Act on it, or record it where it belongs (the docs in `docs/`, `INSIGHTS.md`, or a report to the Spite language
   session when it is about the language).
2. Then delete it from the inbox. Leave only the header and notes that are not handled yet.

Notes about the language itself go to `D:\Projects\SpiteLanguage\mortaros_notes.md`, which the language session
empties the same way.

## What to read

- [`README.md`](README.md) and [`docs/`](docs/README.md): what exists and how to use it.
- [`docs/conventions.md`](docs/conventions.md): folders, naming, and the rules Spite's compiler enforces.
- [`INSIGHTS.md`](INSIGHTS.md): what building the engine taught us about Spite, and every bug reported upstream.

## How to work

- Compile and run from `examples/` with `D:/Projects/SpiteLanguage/bin/spite <example>`; see
  [`docs/testing.md`](docs/testing.md) for the test programs.
- Report compiler bugs and documentation that keeps causing mistakes to the "Language implementation review"
  session, with a priority based on whether SlopEngine uses the feature.
- Mortaro decides the API. Mark your own proposals as proposals in the docs.

## Commits

The same conventions as the Spite language repository. Start every message with one gitmoji, then a lowercase
imperative summary: ✨ feature · 🐛 bugfix · 📝 docs · ♻️ refactor · ✅ tests · 🔥 removal · ⚡ performance ·
🚨 lints · 🏗️ structure · 🔒 security · ⏪ revert. End it with the model that wrote it, named as the model you are
actually running as:

```
Co-authored-by: Claude Opus 5.5 <noreply@anthropic.com>
```

`scripts/hooks/commit-msg` rejects a message without that trailer; each clone runs
`git config core.hooksPath scripts/hooks` once. `examples/` is not committed for now.
