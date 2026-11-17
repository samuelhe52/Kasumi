# 002.021 — Telari first-screen diagnostic

Telari 0.6.3 includes a built-in diagnostic:

```sh
/Applications/Telari.app/Contents/MacOS/Telari \
  --open-report /absolute/path/to/document.md --json 1179
```

The final argument is content width in points. It reports file-reading, parsing,
controller-setup and first-screen layout times, plus total and first-screen block
counts. Use it to investigate opening performance and how preparation scales
with document size. It does not measure full GUI startup, display latency or
scrolling FPS.
