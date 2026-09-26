# Changelog

## 1.0.3

**Security**
- Reading the calendar is bounded. The whole answer from Olook was collected
  and parsed with no limit on its size or on how long it could take, so a
  very large calendar could swell the shell and a read that never finished
  left the widget "loading" for good. Now Olook is asked for at most 1500
  appointments with long text cut (Olook 1.2.2 or later; an older Olook is
  asked the old way), an answer over 8 MB is not parsed, and a read that
  takes more than 30 seconds is ended and tried again later.

## 1.0.2

**Security**
- Reminders are bounded. Each was a notify-send process living until its
  popup was answered, one per appointment, so a published calendar with
  hundreds of appointments in the next hour started hundreds of processes and
  popups. Now at most three wait at once, appointments due together become one
  summary ("200 appointments starting soon"), each reminder lets go after ten
  minutes, and the record of reminders already given no longer grows forever.

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
