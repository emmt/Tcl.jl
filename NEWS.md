# User visible changes in `Tcl`

This page describes the most important changes in `Tcl`. The format is based on [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic
Versioning](https://semver.org).


## Unreleased

### Fixed

- Raw pointers in C calls are protected by having their owner object preserved from being
  garbage collected.

- Getting a single char from a Tcl object works for multi-byte sequences.

## Changed

- Artifacts `Tcl_jll` and `Tk_jll` are used instead of system libraries.

- `Tcl.doevents` has been deprecated and replaced by `Tcl.do_events` which returns the
  number of processed events.

### New

- `Tcl.do_one_event(flags)` to process any pending events matching `flags`.
