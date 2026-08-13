---
name: english-vocab
description: Capture English words/phrases the user learns during work into a persistent notebook, quiz them for review (spaced repetition), review recurring correction weak points, and export to Anki. Use when the user says things like "log this word", "save that phrase", "add to my vocab", "残しておいて" (about an English term just glossed), or wants to "quiz me", "review my English", "今日の単語テスト", "復習させて", "review my weak points", "弱点を復習", "export to Anki", "Ankiに書き出して". Pairs with the English Tutor output style — it turns in-flight glosses and corrections into a reviewable corpus.
---

# english-vocab

A lightweight vocabulary notebook for an upper-intermediate developer who is
learning English *through* real coding work. It has two jobs: **log** new
terms into a persistent file, and **quiz** the user on them later using a simple
Leitner (spaced-repetition) box system.

The notebook lives at `~/.config/claude/english/vocab.md`. The weakness log lives
at `~/.config/claude/english/mistakes.md`. Always read/write those files (expand
`~` to the user's home). Get today's date with `date +%Y-%m-%d` before writing
any entry or updating a review — never guess the date.

## Entry format

Each entry is a level-3 heading block. Keep it scannable:

```
### spin up
- meaning: 立ち上げる / 起動する（サーバーやインスタンスを）
- note: phrasal verb, casual-technical
- tags: collocation
- example: "Let's ___ a staging env to test this." → spin up — from Builder Suite work
- box: 1 | last: 2026-07-12 | added: 2026-07-12
```

Fields:
- **term** — the word or phrase, lowercased unless it's a proper noun.
- **meaning** — Japanese gloss. Short. Add nuance in parens if it matters.
- **note** — part of speech / register / a false-friend or collocation warning.
  One line, optional but usually helpful.
- **tags** — one or more categories for interleaving quizzes and matching against
  the weakness log: `collocation`, `register`, `word-choice`, `phrasal-verb`,
  `idiom`, `false-friend`, `article`, `preposition`, `jargon`. Optional but
  useful.
- **example** — a real sentence, ideally the one the user actually saw in
  context (cite where). Store it as a **cloze**: blank out the target with `___`
  and put the answer after `→`, so the same line drives fill-in quizzes and Anki
  export. A concrete context is what makes it stick.
- **box** — Leitner level 1–5. New entries start at box 1.
- **last** — date last reviewed (starts = added date).
- **added** — date first logged.

## Logging

When the user asks to save one or more terms:

1. Read `vocab.md`. If a term already exists, **don't duplicate** — instead
   enrich the existing entry (add a better example, sharpen the meaning) and
   leave its box/dates alone.
2. If the user says something vague like "log those" / "残しておいて" right after
   you glossed words in the conversation, pull the terms **from the recent
   glosses/discussion** — don't ask them to retype. Confirm the list briefly.
3. For each new term, write the meaning and note yourself (you're the tutor) —
   don't make the user supply them. Pick an example from the real context if
   there is one; otherwise write a natural, work-flavored sentence.
4. Append entries in the appropriate section (see file layout). Report a
   one-line summary of what you added.

## Quizzing / review

When the user wants to review:

1. Read `vocab.md` and today's date.
2. **Select what's due.** Prioritize, in order: entries never reviewed, then
   lower boxes, then oldest `last` date. A box-N item is "due" roughly every
   `N` days (box1≈daily, box2≈2d, box3≈4d, box4≈8d, box5≈mastered/rarely) —
   approximate from `last` vs today; don't be rigid. Default to ~8 items per
   session unless the user asks for more or fewer. **Interleave tags** — don't
   serve a block of the same category; mix `collocation`, `preposition`, etc.
3. **Quiz style** (mix it up, keep it quick):
   - Show the Japanese meaning → ask for the English term, or
   - Show the term → ask the user to use it in a sentence, or
   - Use the stored cloze (`___`) as a fill-in-the-blank.
   Ask one at a time; wait for the answer before revealing.
4. **Grade generously but honestly.** Correct → box +1 (cap 5). Wrong or "I
   don't know" → reset box to 1. Either way update `last` to today. If the
   user's sentence is grammatical but slightly unnatural, accept it and offer
   the more natural phrasing.
5. **Aim for ~60–70% correct.** That hit rate is where review is productive. If
   the user is acing everything (too easy), pull in more never-reviewed / higher
   items or ask for production (use-in-a-sentence) instead of recognition. If
   they're missing most (too hard), shrink the set and lean on cloze hints.
6. After the round, update the file with new box/last values and give a short
   recap: how many right, and which 2–3 to focus on next time.

## Reviewing weak points

When the user asks to "review my weak points" / "弱点を復習":

1. Read `mistakes.md`. Group the logged corrections by `[category]` and by
   recurrence count (`×N`) to find where they leak most.
2. Report the top 2–3 leaking categories in one line each (e.g. "articles — 6
   hits; prepositions — 4"), then drill them: give the user fresh sentences to
   produce or fix that target the same trap, and recast their answers.
3. This is practice, not bookkeeping — you don't have to mutate `mistakes.md`,
   but you may bump a count if the same mistake recurs during the drill.

## Exporting to Anki

When the user asks to "export to Anki" / "Ankiに書き出して":

1. Read `vocab.md`. Produce a UTF-8 CSV (or TSV) at `~/.config/claude/english/anki-export.csv`.
2. One row per entry, atomic one-fact cards. Suggested columns:
   `Front` (the cloze sentence with `___`), `Back` (the term), `Extra`
   (meaning JP + note + tags). For a native cloze deck, alternatively emit
   `{{c1::term}}` inline in the sentence.
3. Tell the user how to import (Anki → File → Import, set the field mapping,
   delimiter, and "Allow HTML" off). Mention the `raine/anki-llm` copy-mode path
   as an alternative if they'd rather generate richer cards.
4. Don't delete anything from `vocab.md` on export — it stays the source of truth.

## Style

- Keep it fast and low-friction — this runs alongside real work, it isn't a
  classroom. No long preambles.
- Respond in English (matching the English Tutor mode), but keep Japanese
  glosses in the `meaning` field.
- Never rewrite or reorder the whole file gratuitously — edit only the entries
  you touched, so the diff stays small and the file stays stable.
