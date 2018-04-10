# Automatically named objects.

const __counter = Dict{String,Int}()

"""
    autoname(pfx = "jl_auto")

yields a unique name with given prefix.  The result is a string of the form
`pfx#` where `#` is a unique number for that prefix.
"""
function autoname(pfx::AbstractString = "jl_auto")
    global __counter
    n = get(__counter, pfx, 0) + 1
    __counter[pfx] = n
    return pfx*string(n)
end

#------------------------------------------------------------------------------
# Mangement of Tcl objects.

"""
    TclObj(value)

yields a new instance of `TclObj` which stores a Tcl object pointer.  This
method may be overloaded to implement means to pass other kinds of arguments to
Tcl.  Tcl objects are used to efficiently build Tcl commands in the form of
`TclObj{List}`.

"""
@inline TclObj(value::Bool) =
    TclObj{Bool}(ccall((:Tcl_NewBooleanObj, libtcl), TclObjPtr,
                       (Cint,), (value ? one(Cint) : zero(Cint))))

if Cint != Clong
    @inline TclObj(value::Cint) =
        TclObj{Cint}(ccall((:Tcl_NewIntObj, libtcl), TclObjPtr,
                           (Cint,), value))
end

@inline TclObj(value::Clong) =
    TclObj{Clong}(ccall((:Tcl_NewLongObj, libtcl), TclObjPtr,
                        (Clong,), value))

if Clonglong != Clong
    @inline TclObj(value::Clonglong) =
        TclObj{Clonglong}(ccall((:Tcl_NewWideIntObj, libtcl), TclObjPtr,
                     (Clonglong,), value))
end

@inline TclObj(value::Cdouble) =
    TclObj{Cdouble}(ccall((:Tcl_NewDoubleObj, libtcl), TclObjPtr,
                          (Cdouble,), value))

@inline TclObj(value::T) where {T<:Integer} =
    TclObj(convert((sizeof(T) ≤ sizeof(Cint) ? Cint : Clong), value))

@inline TclObj(value::Union{Irrational,Rational,AbstractFloat}) =
    TclObj(convert(Cdouble, value))

# There are two alternatives to create Tcl string objects: `Tcl_NewStringObj`
# or `Tcl_NewUnicodeObj`.  After some testings (see my notes), the following
# works correctly.  To build a Tcl object from a Julia string, use `Ptr{UInt8}`
# instead of `Cstring` and provide the number of bytes with `sizeof(str)`.
@inline __newobj(str::AbstractString, nbytes::Integer = sizeof(str)) =
    ccall((:Tcl_NewStringObj, libtcl), TclObjPtr,
           (Ptr{UInt8}, Cint), str, nbytes)

@inline TclObj(str::AbstractString) = TclObj{String}(__newobj(str))

@inline TclObj(value::Symbol) = TclObj(string(value))

@inline TclObj(::Void) = TclObj{Void}(__newobj(NOTHING, 0))

@inline TclObj(obj::TclObj) = obj

@inline TclObj(f::Function) =
    TclObj{Command}(__newobj(createcommand(__currentinterpreter[], f)))

TclObj(tup::Tuple) = list(tup...)

TclObj(vec::AbstractVector) = list(vec...)

TclObj(::T) where T =
    tclerror("making a Tcl object for type $T is not supported")

# FIXME: for a byte array object, some means to prevent garbage collection of
# the array are needed.
#
# TclObj(arr::Vector{UInt8}) =
#    ccall((:Tcl_NewByteArrayObj, libtcl), TclObjPtr, (Ptr{UInt8}, Cint),
#          arr, sizeof(arr))

# Julia takes care of managing its objects so we just need to add a single
# reference for Julia for any Tcl object returned by Tcl library and make sure
# that the refrence count is decremented when the Julia object is finalized.
#
# The following methods correspond to the Tcl macros which are provided to
# increment and decrement a Tcl_Obj's reference count, and to test whether an
# object is shared (i.e. has reference count > 1).
#
# The reference count of a Tcl object is an `int` which is the first member of
# the Tcl_Obj structure and we directly address it using "unsafe" operations.

@inline function __getrefcount(obj::TclObj)
    return unsafe_load(Ptr{Cint}(obj.ptr))
end

@inline function __incrrefcount(obj::TclObj)
    ptr = Ptr{Cint}(obj.ptr)
    unsafe_store!(ptr, unsafe_load(ptr) + one(Cint))
    return obj
end

@inline function __decrrefcount(obj::TclObj)
    ptr = Ptr{Cint}(obj.ptr)
    refcount = unsafe_load(ptr)
    unsafe_store!(ptr, refcount - one(Cint))
    if refcount ≤ 1
        ccall((:TclFreeObj, libtcl), Void, (TclObjPtr,), obj.ptr)
    end
    return nothing
end

@inline function __isshared(obj::TclObj)
    return (unsafe_load(Ptr{Cint}(obj.ptr)) > one(Cint))
end

#------------------------------------------------------------------------------
# List of objects.

"""
    list([interp,] args...; kwds...)

yields a list of Tcl objects consisting of the one object per argument
`args...` (in the same order as they appear) and then followed by two objects
per keyword, say `key=val`, in the form `-key`, `val` (note the hyphen in front
of the keyword name).  To allow for option names that are Julia keywords, a
leading underscore is stripped, if any, in `key`.

"""
function list(args...; kwds...) :: TclObj{List}
    ptr = ccall((:Tcl_NewListObj, libtcl), TclObjPtr,
                (Cint, Ptr{TclObjPtr}), 0, C_NULL)
    ptr != C_NULL || tclerror("failed to allocate new list object")
    return lappend!(TclObj{List}(ptr), args...; kwds...)
end

function list(interp::TclInterp, args...; kwds...) :: TclObj{List}
    local lst
    __currentinterpreter[] = interp
    try
        lst = list(args...; kwds...)
    finally
        __currentinterpreter[] = __initialinterpreter[]
    end
    return lst
end

Base.length(lst::TclObj{List}) = llength(lst)
Base.push!(lst::TclObj{List}, args...; kwds...) =
    lappend!(lst, args...; kwds...)

function llength(lst::TclObj{List}) :: Int
    len = Ref{Cint}(0)
    code = ccall((:Tcl_ListObjLength, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Ptr{Cint}),
                 C_NULL, lst.ptr, len)
    code == TCL_OK || tclerror("failed to query length of list")
    return len[]
end

"""
    lappend!(lst, args...; kwds...)

appends to the list `lst` of Tcl objects one object per argument `args...` (in
the same order as they appear) and then followed by two objects per keyword,
say `key=val`, in the form `-key`, `val` (note the hyphen in front of the
keyword name).  To allow for option names that are Julia keywords, a leading
underscore is stripped, if any, in `key`; for instance:

     lappend!(lst, _in="something")

appends `-in` and `something` in the list `lst`.

"""
function lappend!(lst::TclObj{List}, obj::TclObj)
    code = ccall((:Tcl_ListObjAppendElement, libtcl),
             Cint, (TclInterpPtr, TclObjPtr, TclObjPtr),
                 C_NULL, lst.ptr, obj.ptr)
    code == TCL_OK || tclerror("failed to append new object to list")
    return lst
end

lappend!(lst::TclObj{List}, value) = lappend!(lst, TclObj(value))

function lappend!(lst::TclObj{List}, args...; kwds...)
    for arg in args
        lappend!(lst, arg)
    end
    for (key, val) in kwds
        lappendoption!(lst, key, val)
    end
    return lst
end

lappendoption!(lst::TclObj{List}, key::Name, value) =
    lappendoption!(lst, string(key), value)

lappendoption!(lst::TclObj{List}, key::AbstractString, value) =
    lappend!(lst, TclObj("-"*(key[1] == '_' ? key[2:end] : key)), value)

#------------------------------------------------------------------------------
# Management of Tcl interpreters.

"""
When Tcl package is imported, an initial interpreter is created which can be
retrieved by:

    interp = Tcl.getinterp()

A new Tcl interpreter can also be created by the command:

    interp = TclInterp()

The resulting object can be used as a function to evaluate a Tcl script, for
instance:

    interp("set x 45")

which yields the result of the script (here the string "45").  An alternative
syntax is:

    interp("set", "x", 45)

The object can also be used as an array to access global Tcl variables (the
variable name can be specified as a string or as a symbol):

    interp["x"]          # yields value of variable "x"
    interp[:tcl_version] # yields version of Tcl
    interp[:x] = 33      # set the value of "x" and yields its value
                         # (as a string)

The Tcl interpreter is initialized and will be deleted when no longer in use.
If Tk has been properly installed, then:

    interp("package require Tk")

should load Tk extension and create the "." toplevel Tk window.  But see
`tkstart` method to load Tk.

"""
function TclInterp(permanent::Bool=false)
    ptr = ccall((:Tcl_CreateInterp, libtcl), Ptr{Void}, ())
    ptr != C_NULL || tclerror("unable to create Tcl interpreter")
    obj = TclInterp(ptr)
    if ! permanent
        __preserve(ptr)
        finalizer(obj, __finalize)
    end
    code = ccall((:Tcl_Init, libtcl), Cint, (Ptr{Void},), ptr)
    code == TCL_OK || tclerror("unable to initialize Tcl interpreter")
    return obj
end

function __finalize(interp::TclInterp)
    # According to Tcl doc. Tcl_Release should be finally called after
    # Tcl_DeleteInterp.
    __deleteinterp(interp)
    __release(interp.ptr)
end

(interp::TclInterp)(args...; kwds...) = evaluate(interp, args...; kwds...)

isdeleted(interp::TclInterp) =
    ccall((:Tcl_InterpDeleted, libtcl), Cint,
          (TclInterpPtr,), interp.ptr) != zero(Cint)

isactive(interp::TclInterp) =
    ccall((:Tcl_InterpActive, libtcl), Cint, (TclInterpPtr,),
          interp.ptr) != zero(Cint)

__preserve(ptr::Ptr{Void}) =
    ccall((:Tcl_Preserve, libtcl), Void, (Ptr{Void},), ptr)

__release(ptr::Ptr{Void}) =
    ccall((:Tcl_Release, libtcl), Void, (Ptr{Void},), ptr)

__deleteinterp(interp::TclInterp) =
    ccall((:Tcl_DeleteInterp, libtcl), Void, (TclInterpPtr,), interp.ptr)


#------------------------------------------------------------------------------
# Evaluation of Tcl scripts.

"""
    Tcl.setresult([interp,] args...) -> nothing

set result stored in Tcl interpreter `interp` or in the initial interpreter if
this argument is omitted.

"""
setresult(interp::TclInterp, obj::TclObj) =
    __setresult(interp, obj)

setresult(interp::TclInterp, result::AbstractString) =
    __setresult(interp, result, TCL_VOLATILE)

# In that specific case, we know that there are no embedded nulls.
setresult(interp::TclInterp, ::Union{Void,TclObj{Void}}) =
    __setresult(interp, EMPTY, TCL_STATIC)

setresult(args...) =
    setresult(getinterp(), args...)

setresult(interp::TclInterp, args...) =
    setresult(interp, list(args...))

setresult(interp::TclInterp, value::Value) =
    setresult(interp, TclObj(value))

# To set Tcl interpreter result, we can call `Tcl_SetObjResult` for any object,
# or `Tcl_SetResult` but only for string results with no embedded nulls (Julia
# will complain about that when converting the argument to `Cstring` so calling
# `Tcl_SetResult` is always safe but may throw an exception).

__setresult(interp::TclInterp, obj::TclObj) =
    ccall((:Tcl_SetObjResult, libtcl), Void, (TclInterpPtr, TclObjPtr),
          interp.ptr, obj.ptr)

__setresult(interp::TclInterp, str::AbstractString, free::Ptr{Void}) =
    ccall((:Tcl_SetResult, libtcl), Void, (TclInterpPtr, Cstring, Ptr{Void}),
          interp.ptr, str, free)

"""
    Tcl.getresult([interp]) -> str

yields the current result stored in Tcl interpreter `interp` or in the initial
interpreter if this argument is omitted.

"""
getresult() = getresult(getinterp())

getresult(interp::TclInterp) = unsafe_string(__getresult(interp))

# To simplify the use of the Tcl interface, we only support retrieving Tcl
# result or variable value as a string (for now, doing otherwise would require
# to guess object type at runtime).
__getresult(interp::TclInterp) =
    ccall((:Tcl_GetStringResult, libtcl), Cstring, (TclInterpPtr,), interp.ptr)

"""
    tcleval([interp,], arg0, args...; kwds...)

or

    Tcl.evaluate([interp,], arg0, args...; kwds...)

evaluates Tcl script or command with interpreter `interp` (or in the initial
interpreter if this argument is omitted).  The result is returned as a string.

If only `arg0` is present, it may be a `TclListObj` which is evaluated as a
single Tcl command; otherwise, `arg0` is evaluated as a Tcl script and may be
anything, like a string or a symbol, that can be converted into a `TclObj`.

If keywords or other arguments than `arg0` are present, they are used to build
a list of Tcl objects which is evaluated as a single command.  Any Keyword, say
`key=val`, is automatically converted in the pair of arguments `-key` `val` in
this list (note the hyphen before the keyword name).  All keywords appear at
the end of the list in unspecific order.

Use `tcltry` if you want to avoid throwing errors and `Tcl.getresult` to
retrieve the result.

"""
evaluate(args...; kwds...) = evaluate(getinterp(), args...; kwds...)

function evaluate(interp::TclInterp, args...; kwds...)
    tcltry(interp, args...; kwds...) == TCL_OK || tclerror(interp)
    return getresult(interp)
end

const tcleval = evaluate

"""
    tcltry([interp,], arg0, args...; kwds...) -> code

evaluates Tcl script or command with interpreter `interp` (or in the initial
interpreter if this argument is omitted) and return a code like `TCL_OK` or
`TCL_ERROR` indicating whether the script was successful.  The result of the
script can be retrieved with `Tcl.getresult`.  See `tcleval` for a description
of the interpretation of arguments `args...` and keywords `kwds...`.

"""
tcltry(args...; kwds...) = tcltry(getinterp(), args...; kwds...)

tcltry(interp::TclInterp, arg0, args...; kwds...) =
    tcltry(interp, list(interp, arg0, args...; kwds...))

tcltry(interp::TclInterp, obj::TclObj) = __eval(interp, obj)

function tcltry(interp::TclInterp, arg0)
    local code
    __currentinterpreter[] = interp
    try
        code = __eval(interp, TclObj(arg0))
    finally
        __currentinterpreter[] = __initialinterpreter[]
    end
    return code
end

#__eval(interp::TclInterp, script::String) =
#    ccall((:Tcl_Eval, libtcl), Cint, (TclInterpPtr, Cstring),
#          interp.ptr, script)

# We use `Tcl_EvalObjEx` and not `Tcl_EvalEx` to evaluate a script
# because the script may contain embedded nulls.
@inline function __eval(interp::TclInterp, obj::TclObj,
                        flags::Integer = TCL_EVAL_GLOBAL|TCL_EVAL_DIRECT)
    code = ccall((:Tcl_EvalObjEx, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Cint),
                 interp.ptr, obj.ptr, flags)
    return code
end

@inline function __eval(interp::TclInterp, lst::TclObj{List},
                        flags::Integer = TCL_EVAL_GLOBAL)
    objc = Ref{Cint}(0)
    objv = Ref{Ptr{TclObjPtr}}(C_NULL)
    code = ccall((:Tcl_ListObjGetElements, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Ptr{Cint}, Ptr{Ptr{TclObjPtr}}),
                 interp.ptr, lst.ptr, objc, objv)
    if code == TCL_OK
        code = ccall((:Tcl_EvalObjv, libtcl), Cint,
                     (TclInterpPtr, Cint, Ptr{TclObjPtr}, Cint),
                     interp.ptr, objc[], objv[], flags)
    end
    return code
end

#------------------------------------------------------------------------------
# Initial Tcl interpreter.

# Many things do not work properly (e.g. freeing a Tcl object yield a
# segmentation fault) if no interpreter has been created, so we always create
# an initial Tcl interpreter.
const __initialinterpreter = Ref{TclInterp}()

# Interpreter for callbacks and objects which need a Tcl interpreter.
const __currentinterpreter = Ref{TclInterp}()

"""
    Tcl.getinterp()

yields the initial Tcl interpreter which is used by default by many methods.
An argument can be provided:

    Tcl.getinterp(w)

yields the Tcl interpreter for widget `w`.

"""
getinterp() = __initialinterpreter[]


#------------------------------------------------------------------------------
# Exceptions

"""
    tclerror(arg)

throws a `TclError` exception, argument `arg` can be the error message as a
string or a Tcl interpreter (in which case the error message is assumed to be
the current result of the Tcl interpreter).

"""
tclerror(msg::AbstractString) = throw(TclError(string(msg)))
tclerror(interp::TclInterp) = tclerror(getresult(interp))

"""
    geterrmsg(ex)

yields the error message associated with exception `ex`.

"""
geterrmsg(ex::Exception) = sprint(io -> showerror(io, ex))

#------------------------------------------------------------------------------
# Processing Tcl/Tk events.  The function `doevents` must be repeatedly
# called too process events when Tk is loaded.

"""
    Tcl.resume()

resumes or starts the processing of Tcl/Tk events.  This manages to repeatedly
call function `Tcl.doevents`.  The method `Tcl.suspend` can be called to
suspend the processing of events.

Calling `Tcl.resume` is mandatory when Tk extension is loaded.  Thus:

    Tcl.evaluate(interp, "package require Tk")
    Tcl.resume()

is the recommended way to load Tk package.  Alternatively:

    Tcl.tkstart(interp)

can be called to do that.

"""
function resume()
    global __timer
    if ! (isdefined(:__timer) && isopen(__timer))
        __timer = Timer(doevents, 0.1, 0.01)
    end
end

"""
    Tcl.suspend()

suspends the processing of Tcl/Tk events for all interpreters.  The method
`Tcl.resume` can be called to resume the processing of events.

"""
function suspend()
    global __timer
    if isdefined(:__timer) && isopen(__timer)
        close(__timer)
    end
end

"""
    Tcl.doevents(flags = TCL_DONT_WAIT|TCL_ALL_EVENTS)

processes Tcl/Tk events for all interpreters.  Normally this is automatically
called by the timer set by `Tcl.resume`.

"""
doevents(::Timer) = doevents()

function doevents(flags::Integer = TCL_DONT_WAIT|TCL_ALL_EVENTS)
    while ccall((:Tcl_DoOneEvent, libtcl), Cint, (Cint,), flags) != 0
    end
end

#------------------------------------------------------------------------------
# Dealing with Tcl variables.

const VARFLAGS = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG

"""
    Tcl.getvar([interp,] var, flags=Tcl.VARFLAGS)

yields the value of variable `var` in Tcl interpreter `interp` or in the
initial interpreter if this argument is omitted.  For efficiency reasons, if
the variable name `var` is a string or a symbol, it must not have embedded
nulls.  It is always possible to wrap the variable name into a `TclObj` to
support variable names with embedded nulls.

"""
getvar(args...) = getvar(getinterp(), args...)

getvar(interp::TclInterp, var::Symbol, args...) =
    getvar(interp, string(var), args...)

function getvar(interp::TclInterp, var::AbstractString, args...)
    ptr = __getvar(interp, var, args...)
    ptr != C_NULL || tclerror(interp)
    return unsafe_string(ptr)
end

function getvar(interp::TclInterp, var::TclObj, args...)
    ptr = __getvar(interp, var, args...)
    ptr != C_NULL || tclerror(interp)
    return __string(ptr)
end

__getvar(interp::TclInterp, var::AbstractString, flags::Cint=VARFLAGS) =
    ccall((:Tcl_GetVar, libtcl), Cstring, (TclInterpPtr, Cstring, Cint),
          interp.ptr, var, flags)

__getvar(interp::TclInterp, var::TclObj, flags::Cint=VARFLAGS) =
    ccall((:Tcl_ObjGetVar, libtcl), TclObjPtr,
          (TclInterpPtr, TclObjPtr, TclObjPtr, Cint),
          interp.ptr, var.ptr, C_NULL, flags)

__string(ptr::TclObjPtr) =
    unsafe_string(ccall((:Tcl_GetString, libtcl), Cstring,
                        (TclObjPtr,), ptr))

"""
    Tcl.setvar([interp,] var, value, flags=Tcl.VARFLAGS)

set variable `var` to be `value` in Tcl interpreter `interp` or in the initial
interpreter if this argument is omitted.  The result is the string version of
`value`.  For efficiency reasons, if the variable name `var` is a string or a
symbol, it must not have embedded nulls.  It is always possible to wrap the
variable name into a `TclObj` to support variable names with embedded nulls.

"""
setvar(args...) = setvar(getinterp(), args...)

setvar(interp::TclInterp, var::Symbol, args...) =
    setvar(interp, string(var), args...)

function setvar(interp::TclInterp, var::AbstractString, value::TclObj, args...)
    ptr = __setvar(interp, var, value, args...)
    ptr != C_NULL || tclerror(interp)
    return __string(ptr)
end

function setvar(interp::TclInterp, var::TclObj, value::TclObj, args...)
    ptr = __setvar(interp, var, value, args...)
    ptr != C_NULL || tclerror(interp)
    return __string(ptr)
end

function __setvar(interp::TclInterp, var::AbstractString, value::TclObj,
                  flags::Cint=VARFLAGS)
    ccall((:Tcl_ObjSetVar2Ex, libtcl), TclObjPtr,
          (TclInterpPtr, Cstring, Ptr{Void}, TclObjPtr, Cint),
          interp.ptr, var, C_NULL, value.ptr, flags)
end

function __setvar(interp::TclInterp, var::TclObj, value::TclObj,
                  flags::Cint=VARFLAGS)
    ccall((:Tcl_ObjSetVar2, libtcl), TclObjPtr,
          (TclInterpPtr, TclObjPtr, TclObjPtr, TclObjPtr, Cint),
          interp.ptr, var.ptr, C_NULL, value.ptr, flags)
end

function __setvar(interp::TclInterp, var::AbstractString,
                  value::AbstractString, flags::Cint=VARFLAGS)
    ccall((:Tcl_SetVar, libtcl), Cstring,
          (TclInterpPtr, Cstring, Cstring, Cint),
          interp.ptr, var, value, flags)
end

"""
    Tcl.unsetvar([interp,] var, flags=Tcl.VARFLAGS)

deletes variable `var` in Tcl interpreter `interp` or in the initial
interpreter if this argument is omitted.

"""
unsetvar(args...) = unsetvar(getinterp(), args...)

unsetvar(interp::TclInterp, var::Symbol, args...) =
    unsetvar(interp, TclObj(var), args...)

unsetvar(interp::TclInterp, var::String, args...) =
    __unsetvar(interp, var, args...) == TCL_OK || tclerror(interp)

__unsetvar(interp::TclInterp, var::String, flags::Cint=VARFLAGS) =
    ccall((:Tcl_UnsetSetVar, libtcl), Cint, (TclInterpPtr, Cstring, Cint),
          interp.ptr, var, flags)


"""
    Tcl.exists([interp,] var, flags=Tcl.VARFLAGS)

checks whether variable `var` is defined in Tcl interpreter `interp` or in the
initial interpreter if this argument is omitted.

"""
exists(var::Name, args...) = exists(getinterp(), var, args...)

exists(interp::TclInterp, var::Symbol, args...) =
    exists(interp, string(var), args...)

exists(interp::TclInterp, var, args...) =
    exists(interp, TclObj(var), args...)

exists(interp::TclInterp, var::AbstractString, args...) =
    __getvar(interp.ptr, var, args...) != C_NULL

exists(interp::TclInterp, var::TclObj, args...) =
    __getvar(interp.ptr, var, args...) != C_NULL


#------------------------------------------------------------------------------
# Implement callbacks.

# Dictionary of objects shared with Tcl to make sure they are not garbage
# collected until Tcl deletes their reference.
const __references = Dict{Any,Int}()

function preserve(obj)
    __references[obj] = get(__references, obj, 0) + 1
end

function release(obj)
    if haskey(__references, obj)
        if __references[obj] > 1
            __references[obj] -= 1
        else
            pop!(__references, obj)
        end
    end
    nothing
end

function __releaseobject(ptr::Ptr{Void}) :: Void
    release(unsafe_pointer_to_objref(ptr))
end

function __evalcommand(fptr::Ptr{Void}, iptr::Ptr{Void},
                       argc::Cint, argv::Ptr{Cstring}) :: Cint
    f = unsafe_pointer_to_objref(fptr)
    interp = TclInterp(iptr)
    args = [unsafe_string(unsafe_load(argv, i)) for i in 1:argc]
    try
        return __setcommandresult(interp, f(args...))
    catch ex
        #println("error during Tk callback: ")
        #Base.display_error(ex, catch_backtrace())
        setresult(interp, "(callback error) " * geterrmsg(ex))
        return TCL_ERROR
    end
end

# With precompilation, `__init__()` carries on initializations that must occur
# at runtime like `cfunction` which returns a raw pointer.
const __releaseobject_ref = Ref{Ptr{Void}}()
const __evalcommand_ref = Ref{Ptr{Void}}()
function __init__()
    __initialinterpreter[] = TclInterp(true)
    __currentinterpreter[] = __initialinterpreter[]
    __releaseobject_ref[] = cfunction(__releaseobject, Void, (Ptr{Void},))
    __evalcommand_ref[] = cfunction(__evalcommand, Cint,
                                    (Ptr{Void}, Ptr{Void}, Cint, Ptr{Cstring}))
end

# If the function provides a return code, we do want to return it to the
# interpreter, otherwise TCL_OK is assumed.
__setcommandresult(interp::TclInterp, result::Tuple{Cint,Any}) =
    __setcommandresult(interp, result[1], result[2])

__setcommandresult(interp::TclInterp, result::Any) =
    __setcommandresult(interp, TCL_OK, result)

__setcommandresult(interp::TclInterp, code::Cint, obj::TclObj) =
    error("not yet implemented")

__setcommandresult(interp::TclInterp, code::Cint, value::Any) =
    __setcommandresult(interp, code, __newobj(value))

function __setcommandresult(interp::TclInterp, code::Cint, ::Void)
    __setresult(interp, NOTHING, TCL_STATIC)
    return code
end

function __setcommandresult(interp::TclInterp, code::Cint,
                            result::AbstractString)
    __setresult(interp, result, TCL_VOLATILE)
    return code
end

"""
       Tcl.createcommand([interp,] [name,] f) -> name

creates a command named `name` in Tcl interpreter `interp` (or in the initial
Tcl interpreter if this argument is omitted).  If `name` is missing
`autoname("jl_callback")` is used to automatically define a name.  The command
name is returned as a string.  The Tcl command will call the Julia function `f`
as follows:

    f(name, arg1, arg2, ...)

where all arguments are strings and the first one is the name of the command.

If the result of the call is a tuple of `(code, value)` of respective type
`(Cint, String)` then `value` is stored as the interpreter result while `code`
(one of `TCL_OK`, `TCL_ERROR`, `TCL_RETURN`, `TCL_BREAK` or `TCL_CONTINUE`) is
returned to Tcl.

The result can also be a scalar value (string or real) which is stored as the
interpreter result and `TCL_OK` is returned to Tcl.  A result which is
`nothing` is the same as an empty string.

See also: `Tcl.deletecommand`
"""
createcommand(f::Function) =
    createcommand(getinterp(), f)

createcommand(name::Name, f::Function) =
    createcommand(getinterp(), name, f)

createcommand(interp::TclInterp, f::Function) =
    createcommand(interp, autoname("jl_callback"), f)

createcommand(interp::TclInterp, name::Symbol, f::Function) =
    createcommand(interp, string(name), f)

function createcommand(interp::TclInterp, name::String, f::Function)
    # Before creating the command, make sure object is not garbage collected
    # until Tcl deletes its reference.
    preserve(f)
    ptr = ccall((:Tcl_CreateCommand, libtcl), Ptr{Void},
                (TclInterpPtr, Cstring, Ptr{Void}, Ptr{Void}, Ptr{Void}),
                interp.ptr, name, __evalcommand_ref[], pointer_from_objref(f),
                __releaseobject_ref[])
    if ptr == C_NULL
        release(f)
        tclerror(interp)
    end
    return name
end

"""
    Tcl.deletecommand([interp,] name)

deletes a command named `name` in Tcl interpreter `interp` (or in the initial
Tcl interpreter if this argument is omitted).

See also: `Tcl.createcommand`
"""
deletecommand(name::Name) = deletecommand(getinterp(), name)

deletecommand(interp::TclInterp, name::Symbol) =
    deletecommand(interp, string(name))

function deletecommand(interp::TclInterp, name::String)
    code = ccall((:Tcl_DeleteCommand, libtcl), Cint,
                 (TclInterpPtr, Cstring), interp.ptr, name)
    if code != TCL_OK
        tclerror(interp)
    end
    return nothing
end
