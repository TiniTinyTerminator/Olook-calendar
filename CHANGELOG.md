# Changelog

## 1.0.1

- Appointment titles and places, which come from whoever published the
  calendar, are only ever shown as plain text; an `<img>` in one could fetch
  a URL.
- Reminders pass the title to `notify-send` safely: a title starting with "-"
  is not read as an option, and the body is escaped.
- Screenshots, and SECURITY.md on reporting a vulnerability.
- Needs Olook 1.1.0 or later; 1.2.0 is recommended for its security fixes.

## 1.0.0

The first release: a clock that stands in for Omarchy's, laid out like its
popup, with your appointments from Olook.
