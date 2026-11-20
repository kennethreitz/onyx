---
type: essay
lang: en
---
# On Typesetting a Note

> Simplicity is about subtracting the obvious and adding the meaningful.
> -- John Maeda

*November 2026*

"Typography exists to honor content," Robert Bringhurst wrote, and a reading view is a promise kept or broken in the details. The PSF ships Python; HTTP carries requests; the API is a contract. None of that should shout in full capitals in the middle of a sentence.[^caps] It's the '90s habit of setting acronyms at full height that makes a page look like a ransom note -- and it's easy to fix.

A good page has a measure of about sixty-five characters, a steady baseline, and margins that look straight to the eye even when they aren't...[^optical] Dashes come in three lengths: the hyphen in *well-known*, the en dash in 1914--1918, and the em dash---which interrupts. Ellipses are one glyph, not three periods. "Quotes," she said, "should curl 'the right way' around words."

Three notes in one short paragraph.[^a] They must not collide.[^b] Each one finds room below the last.[^c] Here is a margin note without a number.[^m]

## Figures and Tables

Numbers in running text use old-style figures: 1,234 downloads in 2011, 300 million a month by 2026. In tables the figures line up.

Table: Monthly downloads, in millions.

| Year | Requests | urllib3 | Share |
| ---- | -------: | ------: | ----: |
| 2016 | 4.2 | 5.1 | 45% |
| 2021 | 61.0 | 70.4 | 46% |
| 2026 | 302.5 | 341.9 | 47% |

![A line rising, then flattening](chart.svg "Downloads per month, 2011–2026. The curve rises and then flattens.")

## Code Is Left Alone

Straight quotes inside `"code"` stay straight, and so do these:

```python
print("--- don't touch ---")  # HTTP 200 ... "ok"
```

World War II, Henry VIII and Part IV keep their roman numerals at full height. WHEN SOMEONE SHOUTS THREE WORDS, it stays a shout.

[^caps]: Small caps are drawn, not shrunk: the strokes match the weight of the lowercase. Latin Modern ships them as LM Roman Caps.
[^optical]: Optical margin alignment hangs punctuation slightly outside the text block so the edge reads as straight.
[^a]: The first of three notes, long enough to run several lines in the margin so that it would overlap the next one if nothing pushed it down out of the way.
[^b]: The second note, also long enough to run over three or four lines of the margin column at this width.
[^c]: The third note is pushed down as well.
[^m]: {-} A margin note: Tufte's unnumbered aside, written `[^m]: {-} text`.
