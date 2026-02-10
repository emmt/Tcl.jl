# Julia interface to Tcl/Tk

[![License](http://img.shields.io/badge/license-MIT-brightgreen.svg?style=flat)](LICENSE.md)
[![Build Status](https://github.com/emmt/Tcl.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/emmt/Tcl.jl/actions/workflows/CI.yml?query=branch%3Amain)

This package provides an optimized Julia interface to
[Tcl/Tk](http://www.tcl.tk/).

# Features

* As many Tcl interpreters as needed can be started.  At least one is always
  there and serves as the default interpreter.

* Reading/writing a Tcl variable is as easy as:

  ```julia
  interp[var]             # read Tcl variable value
  interp[var] = val       # set Tcl variable value
  interp[var] = nothing   # unset Tcl variable
  ```

  where `interp` is a Tcl interpreter, `var` is the name of the Tcl variable
  and `val` is its value.

* Consistent conversion between Tcl internal representation of values and Julia
  types.  That is to say, evaluating a Tcl script or getting the value of a Tcl
  variable not necessarily yields a string.  For instance, a Tcl float yields a
  Julia float, a list of integers yields a Julia vector of integers, a list of
  lists yields a vector of vectors, and so on.  Of course, forcing conversion
  to strings is still possible (and easy).

* By avoiding systematic string conversion, faster communication with Tcl/Tk is
  achieved.

* Tcl objects can be manipulated directly in Julia and may be converted to
  Julia values (strings, integers, floats or vectors of these).

* Scripts can be strings but can also be expressed using a syntax which is
  closer to Julia.  For instance, keywords are converted to Tcl options.
  Scripts can also be built as efficient lists of Tcl objects.  Evaluating
  a script is done by:

  ```julia
  Tcl.eval(script)         # evaluate Tcl script in initial interpreter
  Tcl.eval(interp, script) # evaluate Tcl script with specific interpreter
  interp(script)           # idem
  ```

* A number of wrappers are provided to symplify the use of widgets.

* Julia arrays can be used to set Tk images and conversely.  A number of
  methods are provided to apply pseudo-colormaps or retrieve colorplanes or
  alpha channel.  Temporaries and copies are avoided.

* Julia functions may be used as Tk callbacks.


# Alternatives

There exists [another Julia Tk package](http://github.com/JuliaGraphics/Tk.jl)
but with different design choices and some issues I wanted to avoid (for
instance, X conflict with PyPlot when using Gtk backend, Qt backend is OK).
This is why I started this project.  I would be very happy if, eventually, the
two projects merge.


# Installation

Tcl.jl is not yet an [offical Julia package](https://pkg.julialang.org/) but it
is easy to install from the REPL of Julia's package
manager<sup>[[pkg]](#pkg)</sup> as follows:

```julia
pkg> add https://github.com/emmt/Tcl.jl.git
```

where `pkg>` represents the package manager prompt and `https` protocol has
been assumed; if `ssh` is more suitable for you, then:

```julia
pkg> add git@github.com:emmt/Tcl.jl.git
```

To check whether Tcl package works correctly:

```julia
pkg> test Tcl
```

To update to the last version:

```julia
pkg> update Tcl
pkg> build Tcl
```

and perhaps test again...

If something goes wrong, it may be because you already have an old
version of Tcl.jl.  Uninstall Tcl.jl as follows:

```julia
pkg> rm Tcl
pkg> gc
pkg> add https://github.com/emmt/Tcl.jl.git
```

before re-installing.

<hr>

- <a name="pkg"><sup>[pkg]</sup></a> To switch from [julia
  REPL](https://docs.julialang.org/en/stable/manual/interacting-with-julia/) to
  the package manager REPL, just hit the `]` key and you should get a
  `... pkg>` prompt.  To revert to Julia's REPL, hit the `Backspace` key at the
  `... pkg>` prompt.
