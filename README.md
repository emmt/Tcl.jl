# Julia interface to Tcl/Tk

[![License](http://img.shields.io/badge/license-MIT-brightgreen.svg?style=flat)](LICENSE.md)
[![Build Status](https://travis-ci.org/emmt/Tcl.jl.svg?branch=master)](https://travis-ci.org/emmt/Tcl.jl)

This package provides an optimized Julia interface to
[Tcl/Tk](http://www.tcl.tk/).

# Features

* As many Tcl interpreters as needed can be started.  At least one is always
  there and serves as the default interpreter.

* Reading/writting a Tcl variable is as easy as:

  ```julia
  interp[var]             # read Tcl variable value
  interp[var] = val       # set Tcl variable value
  interp[var] = nothing   # unset Tcl variable
  ```

  where `interp` is a Tcl interpreter, `var` is the name of the Tcl variable
  and `val` is its value.

* Consistent conversion between Tcl internal representation of values and Julia
  types.  That is to say, evaluating a Tcl script or getting the value of a Tcl
  variable not necessarily yield a string.  For instance, a Tcl float yields a
  Julia float, a list of integers yields a Julia vector of integers, a list of
  lists yields a vector of vectors, and so on.  Of course, forcing conversion
  to strings is still possible (and easy).

* By avoing string conversion, faster communication with Tcl/Tk is achieved.

* Tcl objects can be manipulated directly in Julia and may be converted to
  Julia values (strings, integers, floats or vectors of these).

* Scripts can be strings but can also be expressed using a syntax which is
  closer to Julia.  For instance, keywords are converted to Tcl options.
  Scripts can also be built as efficient lists of Tcl objects.

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
