#
# basics.jl -
#
# Implement interface to Tcl interpreter, evaluation of scripts, callbacks...
#

# Make TclStatus behaves as an integer when used in comparisons with another
# status or an integer.
for op in (:(==), :(!=), :(<), :(<=), :(>), :(>=))
    @eval begin
        Base.$op(a::TclStatus, b::Integer  ) = $op(a.code, b     )
        Base.$op(a::Integer,   b::TclStatus) = $op(a     , b.code)
        Base.$op(a::TclStatus, b::TclStatus) = $op(a.code, b.code)
    end
end
TclStatus(status::TclStatus) = status
Base.convert(::Type{T}, status::TclStatus) where {T<:Integer} =
    convert(T, status.code)
Base.convert(::Type{Integer}, status::TclStatus) = status.code

#------------------------------------------------------------------------------
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
# Management of Tcl interpreters.

"""
When Tcl package is imported, an initial interpreter is created which can be
retrieved by:

```julia
interp = Tcl.getinterp()
```

A new Tcl interpreter can also be created by the command:

```julia
interp = TclInterp()
```

The resulting object can be used as a function to evaluate a Tcl script, for
instance:

```julia
interp("set x 42")
```

which yields the result of the script (here the string `"42"`).  An alternative
syntax is:

```
interp("set", "x", 42)
```

which yields the value `42`.  See methods [`Tcl.evaluate`](@ref) or
[`Tcl.eval`](@ref) for more details about script evaluation.

The object can also be used as an array to access global Tcl variables (the
variable name can be specified as a string or as a symbol):

```julia
interp["x"]          # yields value of variable "x"
interp[:tcl_version] # yields version of Tcl
interp[:x] = 33      # set the value of "x" and yields its value
```

The Tcl interpreter is initialized and will be deleted when no longer in use.
If Tk has been properly installed, then:

```julia
interp("package require Tk")
```

should load Tk extension and create the "." toplevel Tk window.  But see
`tkstart` method to load Tk.

"""
function TclInterp(permanent::Bool=false)
    if (ptr = Tcl_CreateInterp()) == C_NULL
        Tcl.error("unable to create Tcl interpreter")
    end
    if Tcl_Init(ptr) != TCL_OK
        Tcl_DeleteInterp(ptr)
        Tcl.error("unable to initialize Tcl interpreter")
    end
    obj = TclInterp(ptr)
    if ! permanent
        finalizer(obj, __finalize)
    end
    return obj
end

function __finalize(interp::TclInterp)
    Tcl_DeleteInterp(interp.ptr)
end

(interp::TclInterp)(::Type{T}, args...; kwds...) where {T} =
    Tcl.eval(T, interp, args...; kwds...)

(interp::TclInterp)(args...; kwds...) = Tcl.eval(interp, args...; kwds...)

isdeleted(interp::TclInterp) = Tcl_InterpDeleted(interp.ptr)
isactive(interp::TclInterp) = Tcl_InterpActive(interp.ptr)


#------------------------------------------------------------------------------
# Evaluation of Tcl scripts.

"""
```julia
Tcl.setresult([interp,] args...) -> nothing
```

set result stored in Tcl interpreter `interp` or in the initial interpreter if
this argument is omitted.

"""
setresult() = setresult(getinterp())
setresult(arg) = setresult(getinterp(), arg)
setresult(args...) = setresult(getinterp(), args...)

# To set Tcl interpreter result, we can call `Tcl_SetObjResult` for any object,
# or `Tcl_SetResult` but only for string results with no embedded nulls.  There
# may be a slight advantage for calling `Tcl_SetResult` with non-volatile
# strings as copies are avoided.  Julia strings are immutable but I am not sure
# that they are non-volatile, so I prefer to not try using `Tcl_SetResult` and
# rather use `Tcl_SetObjResult` for any object.
#
# `Tcl_SetObjResult` does manage the reference count of its object argument so
# it is OK to directly pass a temporary object.
setresult(interp::TclInterp) =
    Tcl_SetObjResult(interp.ptr, __objptr())

setresult(interp::TclInterp, arg) =
    Tcl_SetObjResult(interp.ptr, __objptr(arg))

setresult(interp::TclInterp, args...) =
    Tcl_SetObjResult(interp.ptr, __newlistobj(args))

@static if false
    # The code for strings (taking care of embedded nulls and using
    # `Tcl_SetResult` if possible) is written below for reference but not
    # compiled.
    function setresult(interp::TclInterp, str::AbstractString;
                       volatile::Bool = true)
        ptr, siz = Base.unsafe_convert(Ptr{Cchar}, str), sizeof(str)
        if Base.containsnul(ptr, siz)
            # String has embedded NULLs, wrap it into a temporary object.  It
            # is not necessary to dela with its reference count as
            # Tcl_SetObjResult takes care of that.
            Tcl_SetObjResult(interp.ptr, __newstringobj(ptr, siz))
        else
            Tcl_SetResult(interp.ptr, ptr,
                          (volatile ? TCL_VOLATILE : TCL_STATIC))
        end
    end
end

"""
```julia
Tcl.getresult([T=Any,][interp])
```

yields the current result stored in Tcl interpreter `interp` or in the initial
interpreter if this argument is omitted.  If optional argument `T` is omitted,
the type of the returned value reflects that of the internal representation of
the result stored in Tcl interpreter; otherwise, `T` can be used to specify
how Tcl result should be converted (see [`Tcl.getvar`](@ref) for details).

See also: [`Tcl.getvar`](@ref).

"""
getresult() = getresult(getinterp())

getresult(interp::TclInterp) = getresult(Any, interp)

getresult(::Type{T}) where {T} = getresult(T, getinterp())

# Tcl_GetStringResult calls Tcl_GetObjResult, so we only interface to this
# latter function.  Incrementing the reference count of the result is only
# needed if we want to keep a long-term reference to it,
# `__objptr_to(TclObj,...)` takes care of that).
getresult(::Type{T}, interp::TclInterp) where {T} =
    __objptr_to(T, interp.ptr, Tcl_GetObjResult(interp.ptr))

# In case of error, getting a string result is needed, we provide the following
# method.
__errmsg(intptr::TclInterpPtr, defmsg::String) :: String =
    (intptr == C_NULL ? defmsg :
     __objptr_to(String, C_NULL, Tcl_GetObjResult(intptr)))

"""
```julia
Tcl.exec([T,][interp,], args...; kwds...)
```

makes a list of the arguments `args...` and keywords `kwds...` and evaluates it
as a Tcl script.  See [`Tcl.eval`](@ref) for details about optional result type
`T` and Tcl interpreter `interp`.  Any specified keyword, say `key=val`, is
automatically converted in the pair of arguments `-key` `val` in this list
(note the hyphen before the keyword name).  All keywords appear at the end of
the list in unspecific order.

Apart from the accounting of keywords, the main difference with `Tcl.eval` is
that each input argument is interpreted as a different "word" of the Tcl
script.  Using `Tcl.eval`, `Tcl.exec` is equivalent to:

```julia
Tcl.eval([T,][interp,], Tcl.list(args...; kwds...))
```

Specify `T` as `TclStatus`, if you want to avoid throwing errors and call
`Tcl.getresult` to retrieve the result.

See also: [`Tcl.eval`](@ref), [`Tcl.list`](@ref), [`Tcl.getresult`](@ref).

"""
exec(args...; kwds...) = exec(getinterp(), args...; kwds...)

exec(::Type{T}, args...; kwds...) where {T} =
    exec(T, getinterp(), args...; kwds...)

function exec(interp::TclInterp, args...; kwds...)
    exec(TclStatus, interp, args...; kwds...) == TCL_OK || Tcl.error(interp)
    return getresult(interp)
end

function exec(::Type{T}, interp::TclInterp, args...; kwds...) where {T}
    exec(TclStatus, interp, args...; kwds...) == TCL_OK || Tcl.error(interp)
    return getresult(T, interp)
end

# This version gets called when there are any keywords or when zero or more
# than one argument.
function exec(::Type{TclStatus}, interp::TclInterp, args...; kwds...)
    length(args) ≥ 1 || Tcl.error("expecting at least one argument")
    return TclStatus(__evallist(interp, __newlistobj(args...; kwds...)))
end

"""
```julia
Tcl.eval([T,][interp,], args...)
```

concatenates arguments `args...` into a list and evaluates it as a Tcl script
with interpreter `interp` (or in the initial interpreter if this argument is
omitted).  See [`Tcl.concat`](@ref) for details about how arguments are
concatenated into a list.

If optional argument `T` is omitted, the type of the returned value reflects
that of the internal representation of the result of the script; otherwise, `T`
specifies the type of the result (see [`getvar`](@ref) for details).  As a
special case, when `T` is `TclStatus`, `Tcl.eval` behaves like the Tcl `catch`
command: the script is evaluated and no exception get thrown in case of error
but a status such as `TCL_OK` or `TCL_ERROR` is always returned and
[`Tcl.getresult`](@ref) can be used to retrieve the value of the result (which
is an error message if the returned status is `TCL_ERROR`).

Use `Tcl.exec` if you want to consider each argument in `args...` as a distinct
command argument.

Specify `T` as `TclStatus`, if you want to avoid throwing errors and
`Tcl.getresult` to retrieve the result.

See also: [`Tcl.concat`](@ref), [`Tcl.exec`](@ref), [`getvar`](@ref).

"""
Tcl.eval(args...) = Tcl.eval(getinterp(), args...)

Tcl.eval(::Type{T}, args...) where {T} =
    Tcl.eval(T, getinterp(), args...)

function Tcl.eval(interp::TclInterp, args...)
    Tcl.eval(TclStatus, interp, args...) == TCL_OK || Tcl.error(interp)
    return getresult(interp)
end

function Tcl.eval(::Type{T}, interp::TclInterp, args...) where {T}
    Tcl.eval(TclStatus, interp, args...) == TCL_OK || Tcl.error(interp)
    return getresult(T, interp)
end

# This version gets called when there are any keywords or when zero or more
# than one argument.
function Tcl.eval(::Type{TclStatus}, interp::TclInterp, args...)
    length(args) ≥ 1 || Tcl.error("missing script to evaluate")
    listptr = __newlistobj()
    try
        for arg in args
            __concat(listptr, arg)
        end
        return TclStatus(__evallist(interp, listptr))
    finally
        Tcl_DecrRefCount(listptr)
    end
end

# Concatenating a list yields the same list, the following version avoid this
# extra work.
function Tcl.eval(::Type{TclStatus}, interp::TclInterp, cmd::TclObj)
    if __objtype(cmd.ptr) == List
        return TclStatus(__evallist(interp, cmd.ptr))
    end
end

# We use `Tcl_EvalObjEx` and not `Tcl_EvalEx` to evaluate a script because the
# script may contain embedded nulls.  `Tcl_EvalObjEx` does manage the reference
# count of its object argument.

function __eval(interp::TclInterp, objptr::TclObjPtr)
    flags = TCL_EVAL_GLOBAL
    if Tcl_GetRefCount(objptr) < 1
        # For a temporary object there is no needs to compile the script.
        flags |= TCL_EVAL_DIRECT
    end
    return Tcl_EvalObjEx(interp.ptr, objptr, flags)
end

function __evallist(interp::TclInterp, listptr::TclObjPtr)
    flags = TCL_EVAL_GLOBAL
    status, objc, objv = Tcl_ListObjGetElements(interp.ptr, listptr)
    if status == TCL_OK
        status = Tcl_EvalObjv(interp.ptr, objc, objv, flags)
    end
    return status
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
    Tcl.error(arg)

throws a `TclError` exception, argument `arg` can be the error message as a
string or a Tcl interpreter (in which case the error message is assumed to be
the current result of the Tcl interpreter).

"""
Tcl.error(msg::AbstractString) = throw(TclError(string(msg)))
Tcl.error(interp::TclInterp) = Tcl.error(getresult(String, interp))

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

    Tcl.eval(interp, "package require Tk")
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
    while Tcl_DoOneEvent(flags)
    end
end

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

const __releaseobject_ref = Ref{Ptr{Void}}() # will be set by __init__
function __releaseobject(ptr::Ptr{Void}) :: Void
    release(unsafe_pointer_to_objref(ptr))
end

const __evalcommand_ref = Ref{Ptr{Void}}() # will be set by __init__
function __evalcommand(fptr::Ptr{Void}, iptr::TclInterpPtr,
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
function __init__()
    __initialinterpreter[] = TclInterp(true)
    __currentinterpreter[] = __initialinterpreter[]
    __releaseobject_ref[] = cfunction(__releaseobject, Void, (Ptr{Void},))
    __evalcommand_ref[] = cfunction(__evalcommand, Cint,
                                    (Ptr{Void}, TclInterpPtr,
                                     Cint, Ptr{Cstring}))
    __init_types()
end

# If the function provides a return status, we do want to return it to the
# interpreter, otherwise TCL_OK is assumed.
__setcommandresult(interp::TclInterp, result::Tuple{TclStatus,Any}) =
    __setcommandresult(interp, result[1], result[2])

__setcommandresult(interp::TclInterp, result) =
    __setcommandresult(interp, TCL_OK, result)

function __setcommandresult(interp::TclInterp, status::TclStatus, result)
    Tcl_SetObjResult(interp.ptr, __objptr(result))
    return status
end

"""
```julia
Tcl.createcommand([interp,] [name,] f) -> name
```

creates a command named `name` in Tcl interpreter `interp` (or in the initial
Tcl interpreter if this argument is omitted).  If `name` is missing
`Tcl.autoname("jl_callback")` is used to automatically define a name.  The
command name is returned as a string.  The Tcl command will call the Julia
function `f` as follows:

```julia
f(name, arg1, arg2, ...)
```

where all arguments are strings and the first one is the name of the command.

If the result of the call is a tuple of `(status, value)` of respective type
`(TclStatus, String)` then `value` is stored as the interpreter result while
`status` (one of `TCL_OK`, `TCL_ERROR`, `TCL_RETURN`, `TCL_BREAK` or
`TCL_CONTINUE`) is returned to Tcl.

The result can also be a scalar value (string or real) which is stored as the
interpreter result and `TCL_OK` is returned to Tcl.  A result which is
`nothing` is the same as an empty string.

See also: [`Tcl.deletecommand`](@ref), [`Tcl.autoname`](@ref).

"""
createcommand(f::Function) =
    createcommand(getinterp(), f)

createcommand(name::Name, f::Function) =
    createcommand(getinterp(), name, f)

createcommand(interp::TclInterp, f::Function) =
    createcommand(interp, autoname("jl_callback"), f)

createcommand(interp::TclInterp, name::Symbol, f::Function) =
    createcommand(interp, string(name), f)

# FIXME: use object, not string name?
function createcommand(interp::TclInterp, name::String, f::Function)
    # Before creating the command, make sure object is not garbage collected
    # until Tcl deletes its reference.
    preserve(f)
    ptr = Tcl_CreateCommand(interp.ptr,
                            name,
                            __evalcommand_ref[],
                            pointer_from_objref(f),
                            __releaseobject_ref[])
    if ptr == C_NULL
        release(f)
        Tcl.error(interp)
    end
    return name
end

"""
```julia
Tcl.deletecommand([interp,] name)
```

deletes a command named `name` in Tcl interpreter `interp` (or in the initial
Tcl interpreter if this argument is omitted).

See also: [`Tcl.createcommand`](@ref).

"""
deletecommand(name::StringOrSymbol) =
    deletecommand(getinterp(), name)

function deletecommand(interp::TclInterp, name::StringOrSymbol)
    if Tcl_DeleteCommand(interp.ptr, name) != TCL_OK
        Tcl.error(interp)
    end
    return nothing
end
