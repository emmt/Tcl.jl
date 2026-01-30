# User visible changes in `Tcl`

This page describes the most important changes in `Tcl`. The format is based on [Keep a
Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic
Versioning](https://semver.org).


## Unreleased

### Breaking changes

- Instances of `TclObj` no longer have a type parameter as the *type* of a Tcl object
  reflects a cached internal state that may change for efficiency.

- `Tcl.getvalue(obj)` has been replaced by `convert(T, obj)` to get a value of given type
  `T` from Tcl object `obj`.

- List-specialized methods (`llength`, `lappend!`, and `lindex`) have been suppressed in
  favor of the Julia API for collections. Thus, `length`, `append!`, `push!`, `delete!`,
  `getindex`, and `setindex!` shall be used to access Tcl objects as if they are lists.

### Fixed

- Raw pointers in C calls are protected by having their owner object preserved from being
  garbage collected.

- Getting a single char from a Tcl object works for multi-byte sequences.

- To protect the content of shared objects, Tcl imposes a strict copy-on-write policy. Not
  following this policy causes Tcl to panic (i.e., abort the program). To avoid this,
  attempts to modify a shared Tcl object are detected and forbidden by throwing an
  exception.

## Changed

- Artifacts `Tcl_jll` and `Tk_jll` are used instead of system libraries.

- `Tcl.doevents` has been deprecated and replaced by `Tcl.do_events` which returns the
  number of processed events.

- Following Tcl behavior, `obj[i]` yields `missing` if index `i` is out of range.

### Added

- `Tcl.do_one_event(flags)` to process any pending events matching `flags`.
