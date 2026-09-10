# Formera

Google Forms replacement at `https://forms.gapul.net`.

- The visual builder is available in the browser.
- The same forms and responses are available through Formera's REST API.
- `hs forms` logs in with the short-lived token flow automatically.
- The SQLite database and authenticated design uploads are included in the
  daily backup and monthly restore drill.
- Anonymous file uploads are deliberately blocked by the local gateway. Do not
  add a `file` field until upstream requires a form-scoped upload token.

Create a form from a version-controlled JSON definition:

```sh
hs forms create /etc/homelab/formera/example-form.json
hs forms list
hs forms responses FORM_ID
hs forms export FORM_ID csv ./responses.csv
```

Creating starts the form as a draft. Publish it from the UI, or export the full
form with `hs forms get FORM_ID`, change `status` to `published`, then apply it:

```sh
hs forms update FORM_ID ./published-form.json
```

The public URL is `https://forms.gapul.net/f/SLUG`.
