module Tcl

if isfile(joinpath(dirname(@__FILE__),"..","deps","libs.jl"))
    include("../deps/libs.jl")
else
    error("Tcl not properly installed.  Please edit file \"../deps/libs.jl\"")
end

import Base: show, showerror, getindex, setindex!, haskey

# FIXME: I do not like the naming conventions adopted here.
export
    TclInterp,
    TclError,
    tcleval,
    tclsetvar,
    tclunsetvar,
    tclexists,
    tclgetvar,
    tclresume,
    tclsuspend,
    tcldoevents,
    tclresult,
    tclerror

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

immutable TclError <: Exception
    msg::String
end

showerror(io::IO, e::TclError) = print(io, "Tcl/Tk error: ", e.msg)

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
    function TclInterp()
        ptr = ccall((:Tcl_CreateInterp, libtcl), Ptr{Void}, ())
        if ptr == C_NULL
            tclerror("unable to create Tcl interpreter")
        end
        obj = new(ptr)
        finalizer(obj, obj -> ccall((:Tcl_DeleteInterp, libtcl), Void,
                                    (Ptr{Void},), obj.ptr))
        code = ccall((:Tcl_Init, libtcl), Cint, (Ptr{Void},), ptr)
        if code != TCL_OK
            tclerror("unable to initialize Tcl interpreter")
        end
        return obj
    end
end

(interp::TclInterp)(script::String) = tcleval(interp, script)

local tclinterp::TclInterp

tclerror(msg::String) = throw(TclError(msg))
tclerror(interp::TclInterp) = tclerror(tclresult(interp))


# Processing Tcl/Tk events.  The function `tcldoevents` must be repeatedly
# called too process events when Tk is loaded.
local timer::Timer
local counter::Int = 0

function tclsuspend()
    global timer
    if isdefined(:timer) && isopen(timer)
        close(timer)
    end
end

function tclresume()
    global timer
    if ! (isdefined(:timer) && isopen(timer))
        timer = Timer(tcldoevents, 0.1, 0.01)
    end
end

tcldoevents(::Timer) = tcldoevents()

function tcldoevents(flags::Integer = TCL_DONT_WAIT | TCL_ALL_EVENTS)
    while ccall((:Tcl_DoOneEvent, libtcl), Cint, (Cint,), flags) != 0
    end
end

function requiretk(interp::TclInterp)
    tcleval(interp, "package require Tk")
    tclresume()
end

tclresult(interp::TclInterp) =
    unsafe_string(ccall((:Tcl_GetStringResult, libtcl),
                        Ptr{UInt8}, (Ptr{Void},), interp.ptr))

protect(str::String) = "{"*str*"}" # FIXME: Improve this.

function tcleval(interp::TclInterp, script::String)
    code = ccall((:Tcl_Eval,libtcl), Cint, (Ptr{Void}, Ptr{UInt8}),
                 interp.ptr, script)
    result = tclresult(interp)
    if code != TCL_OK
        tclerror(result)
    end
    return result
end

tclsetvar(interp::TclInterp, name::Symbol, args...) =
    tclsetvar(interp, string(name), args...)

tclsetvar(interp::TclInterp, name::String, value::Real, args...) =
    tclsetvar(interp, name, string(value), args...)

function tclsetvar(interp::TclInterp, name::String, value::String,
                   flags::Integer = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
    ptr = ccall((:Tcl_SetVar, libtcl), Ptr{UInt8},
                (Ptr{Void}, Ptr{UInt8}, Ptr{UInt8}, Cint),
                interp.ptr, name, value, flags)
    if ptr == C_NULL
        tclerror(tclresult(interp))
    end
    unsafe_string(ptr)
end

tclunsetvar(interp::TclInterp, name::Symbol, args...) =
    tclunsetvar(interp, string(name), args...)

function tclunsetvar(interp::TclInterp, name::String,
                     flags::Integer = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
    code = ccall((:Tcl_UnsetSetVar, libtcl), Cint,
                (Ptr{Void}, Ptr{UInt8}, Cint),
                 interp.ptr, name, flags)
    if code != TCL_OK
        tclerror(tclresult(interp))
    end
end

tclgetvar(interp::TclInterp, name::Symbol, args...) =
    tclgetvar(interp, string(name), args...)

function tclgetvar(interp::TclInterp, name::String,
                   flags::Integer = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
    ptr = ccall((:Tcl_GetVar, libtcl), Ptr{UInt8},
                (Ptr{Void}, Ptr{UInt8}, Cint),
                interp.ptr, name, flags)
    if ptr == C_NULL
        tclerror(tclresult(interp))
    end
    unsafe_string(ptr)
end

tclexists(interp::TclInterp, name::Symbol,args...) =
    tclexists(interp, string(name), args...)

function tclexists(interp::TclInterp, name::String,
                   flags::Integer = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
    ccall((:Tcl_GetVar, libtcl), Ptr{UInt8}, (Ptr{Void}, Ptr{UInt8}, Cint),
          interp.ptr, key, TCL_GLOBAL_ONLY) != C_NULL
end

# Manage to make any Tcl interpreter usable as a collection with respect to its
# global variables.

getindex(interp::TclInterp, key) = tclgetvar(interp, key)
setindex!(interp::TclInterp, value, key) = tclsetvar(interp, key, value)
haskey(interp::TclInterp, key) = tclexists(interp, key)


include("dialog.jl")
include("photo.jl")

end # module
