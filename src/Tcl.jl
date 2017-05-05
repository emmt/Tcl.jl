module Tcl

if isfile(joinpath(dirname(@__FILE__),"..","deps","libs.jl"))
    include("../deps/libs.jl")
else
    error("Tcl not properly installed.  Please create and edit file \"../deps/libs.jl\"")
end

export
    TclInterp,
    TclError,
    TCL_OK,
    TCL_ERROR,
    TCL_RETURN,
    TCL_BREAK,
    TCL_CONTINUE,
    tclerror

typealias Value  Union{String,Real}
typealias Name   Union{String,Symbol}

const EMPTY = ""

# Codes returned by Tcl fucntions.
const TCL_OK       = convert(Cint, 0)
const TCL_ERROR    = convert(Cint, 1)
const TCL_RETURN   = convert(Cint, 2)
const TCL_BREAK    = convert(Cint, 3)
const TCL_CONTINUE = convert(Cint, 4)

# Flags for settings the result.
const TCL_VOLATILE = convert(Ptr{Void}, 1)
const TCL_STATIC   = convert(Ptr{Void}, 0)
const TCL_DYNAMIC  = convert(Ptr{Void}, 3)

# Flags for Tcl variables.
const TCL_GLOBAL_ONLY    = convert(Cint, 1)
const TCL_NAMESPACE_ONLY = convert(Cint, 2)
const TCL_APPEND_VALUE   = convert(Cint, 4)
const TCL_LIST_ELEMENT   = convert(Cint, 8)
const TCL_LEAVE_ERR_MSG  = convert(Cint, 0x200)

# Flags for Tcl processing events.  Set TCL_DONT_WAIT to not sleep: process
# only events that are ready at the time of the call.  Set TCL_ALL_EVENTS to
# process all kinds of events: equivalent to OR-ing together all of the above
# flags or specifying none of them.
const TCL_DONT_WAIT     = convert(Cint, 1<<1)
const TCL_WINDOW_EVENTS = convert(Cint, 1<<2) # Process window system events.
const TCL_FILE_EVENTS   = convert(Cint, 1<<3) # Process file events.
const TCL_TIMER_EVENTS  = convert(Cint, 1<<4) # Process timer events.
const TCL_IDLE_EVENTS   = convert(Cint, 1<<5) # Process idle callbacks.
const TCL_ALL_EVENTS    = ~TCL_DONT_WAIT      # Process all kinds of events.

# The following values control how blocks are combined into photo images when
# the alpha component of a pixel is not 255, a.k.a. the compositing rule.
const TK_PHOTO_COMPOSITE_OVERLAY = convert(Cint, 0)
const TK_PHOTO_COMPOSITE_SET     = convert(Cint, 1)

"""

A new Tcl interpreter is created by the command:

    interp = TclInterp()

The resulting object can be used as a function to evaluate a Tcl script, for
instance:

    interp("set x 45")

which yields the result of the script (here the string "45").  The object can
also be used as an array to access global Tcl variables (the variable name can
be specified as a string or as a symbol):

    interp["x"]          # yields value of variable "x"
    interp[:tcl_version] # yields version of Tcl
    interp[:x] = 33      # set the value of "x" and yields its value
                         # (as a string)

The Tcl interpreter is initialized and will be deleted when object is no longer
in use.  If Tk has been properly installed, then:

    interp("package require Tk")

should load Tk extension and create the "." toplevel Tk window.

"""
type TclInterp
    ptr::Ptr{Void}
    TclInterp(ptr::Ptr{Void}) = new(ptr)
    function TclInterp()
        ptr = ccall((:Tcl_CreateInterp, libtcl), Ptr{Void}, ())
        if ptr == C_NULL
            tclerror("unable to create Tcl interpreter")
        end
        obj = new(ptr)
        __preserve(ptr)
        finalizer(obj, __finalize)
        code = ccall((:Tcl_Init, libtcl), Cint, (Ptr{Void},), ptr)
        if code != TCL_OK
            tclerror("unable to initialize Tcl interpreter")
        end
        return obj
    end
end

function __finalize(interp::TclInterp)
    __deleteinterp(obj)
    __release(obj.ptr)
end

(interp::TclInterp)(script::String) = evaluate(interp, script)

interpdeleted(interp::TclInterp) = __interpdeleted(interp) != zero(Cint)

immutable TclError <: Exception
    msg::String
end

"""
   tclerror(arg)

throws a `TclError` exception, argument `arg` can be the error message as a
string or a Tcl interpreter (in which case the error message is assumed to be
the current result of the Tcl interpreter).

"""
tclerror(msg::String) = throw(TclError(msg))
tclerror(interp::TclInterp) = tclerror(getresult(interp))

Base.showerror(io::IO, e::TclError) = print(io, "Tcl/Tk error: ", e.msg)

"""
    geterrmsg(ex)

yields the error message associated with exception `ex`.

"""
geterrmsg(ex::Exception) = sprint(io -> showerror(io, ex))

#------------------------------------------------------------------------------
# Default Tcl interpreter.

local __interp::TclInterp

"""
    Tcl.createdefaultinterpreter()

creates a new default Tcl interpreter which replaces the existing one if any.

See also: `Tcl.defaultinterpreter`

"""
createdefaultinterpreter() =
    __interp = TclInterp()


"""
    Tcl.defaultinterpreter()

yields the current default Tcl interpreter, a new one is created if needed.

See also: `Tcl.createdefaultinterpreter`

"""
defaultinterpreter() =
    isdefined(:__interp) ? __interp : createdefaultinterpreter()

#------------------------------------------------------------------------------
# Processing Tcl/Tk events.  The function `doevents` must be repeatedly
# called too process events when Tk is loaded.

local __timer::Timer

function suspend()
    global __timer
    if isdefined(:__timer) && isopen(__timer)
        close(__timer)
    end
end

function resume()
    global __timer
    if ! (isdefined(:__timer) && isopen(__timer))
        __timer = Timer(doevents, 0.1, 0.01)
    end
end

doevents(::Timer) = doevents()

function doevents(flags::Integer = TCL_DONT_WAIT|TCL_ALL_EVENTS)
    while ccall((:Tcl_DoOneEvent, libtcl), Cint, (Cint,), flags) != 0
    end
end

function requiretk(interp::TclInterp)
    evaluate(interp, "package require Tk")
    resume()
end

#------------------------------------------------------------------------------
# Evaluation of Tcl scripts.

setresult(result::Value) = setresult(defaultinterpreter(), value)

setresult(interp::TclInterp, result::Value) =
    unsafe_string(__setresult(interp, result))

setresult(interp::TclInterp, result::Real) =
    unsafe_string(__setresult(interp, result))

getresult() = getresult(defaultinterpreter())

getresult(interp::TclInterp) = unsafe_string(__getresult(interp))

protect(str::String) = "{"*str*"}" # FIXME: Improve this.

evaluate(script::String) = evaluate(defaultinterpreter(), script)

function evaluate(interp::TclInterp, script::String)
    __eval(interp, script) == TCL_OK || tclerror(interp)
    return getresult(interp)
end

#------------------------------------------------------------------------------
# Dealing with Tcl variables.

const VARFLAGS = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG

"""
    Tcl.getvar([interp,] var, flags=Tcl.VARFLAGS)

yields the value of variable `var` in Tcl interpreter `interp` or in the global
interpreter if this argument is omitted.

"""
getvar(name::Name, args...) = getvar(defaultinterpreter(), name, args...)

getvar(interp::TclInterp, name::Symbol, args...) =
    getvar(interp, string(name), args...)

function getvar(interp::TclInterp, name::String, args...)
    ptr = __getvar(interp.ptr, name, args...)
    if ptr == C_NULL
        tclerror(interp)
    end
    unsafe_string(ptr)
end

"""
    Tcl.setvar([interp,] var, value, flags=Tcl.VARFLAGS)

set variable `var` to be `value` in Tcl interpreter `interp` or in the global
interpreter if this argument is omitted.  The result is the string version of
`value`.

"""
setvar(name::Name, args...) = setvar(defaultinterpreter(), name, args...)

setvar(interp::TclInterp, name::Symbol, args...) =
    setvar(interp, string(name), args...)

# FIXME: uset Tcl_ObjSetVar2
setvar(interp::TclInterp, name::String, value::Real, args...) =
    setvar(interp, name, string(value), args...)

function setvar(interp::TclInterp, name::String, value::String, args...)
    ptr = __setvar(interp, name, value, args...)
    if ptr == C_NULL
        tclerror(interp)
    end
    unsafe_string(ptr)
end

"""
    Tcl.unsetvar([interp,] var, flags=Tcl.VARFLAGS)

deletes variable `var` in Tcl interpreter `interp` or in the global interpreter
if this argument is omitted.

"""
unsetvar(name::Name, args...) = unsetvar(defaultinterpreter(), name, args...)

unsetvar(interp::TclInterp, name::Symbol, args...) =
    unsetvar(interp, string(name), args...)

unsetvar(interp::TclInterp, name::String, args...) =
    __unsetvar(interp, name, args...) == TCL_OK || tclerror(interp)


"""
    Tcl.exists([interp,] var, flags=Tcl.VARFLAGS)

checks whether variable `var` is defined in Tcl interpreter `interp` or in the
global interpreter if this argument is omitted.

"""
exists(var::Name, args...) = exists(defaultinterpreter(), var, args...)

exists(interp::TclInterp, var::Symbol, args...) =
    exists(interp, string(var), args...)

exists(interp::TclInterp, var::String, args...) =
    __getvar(interp.ptr, var, args...) != C_NULL

# Manage to make any Tcl interpreter usable as a collection with respect to its
# global variables.

Base.getindex(interp::TclInterp, key) = getvar(interp, key)
Base.setindex!(interp::TclInterp, value, key) = setvar(interp, key, value)
Base.haskey(interp::TclInterp, key) = exists(interp, key)


include("private.jl")
include("callbacks.jl")
include("dialog.jl")
include("photo.jl")

end # module
