Onyx web clipper scripts (see docs/web-clipper.md).

- Readability.js: Mozilla Readability 0.6.0 (https://github.com/mozilla/readability),
  unmodified, from the @mozilla/readability npm package. Apache License 2.0; the full
  text is in LICENSE-Readability.md.
- extract.js: Onyx's own glue (AGPL, like the rest of Onyx). It runs after Readability.js
  in the fetched page and returns the article as XHTML plus metadata.
