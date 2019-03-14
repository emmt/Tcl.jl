#
# basics.jl -
#
# Implement interface to Tcl interpreter, evaluation of scripts, callbacks...
#

#------------------------------------------------------------------------------
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
# Automatically name objects.

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

which yields the value `42`.  See method [`Tcl.eval`](@ref) for more details
about script evaluation.

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
    permanent || finalizer(__finalize, obj)
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


"""
```julia
Tcl.getinterp()
```

yields the initial Tcl interpreter which is used by default by many methods.
An argument can be provided:

```julia
Tcl.getinterp(w)
```

yields the Tcl interpreter for widget (or image) `w`.

"""
getinterp() = __initial_interpreter[]

# This constant wraps a NULL pointer in a TclInterp structure.
const __NO_INTERP = TclInterp(TclInterpPtr(0))

# Many things do not work properly (e.g., freeing a Tcl object yield a
# segmentation fault) if no interpreter has been created, so we always create
# an initial Tcl interpreter (this is done by the __init__ method).
const __initial_interpreter = Ref{TclInterp}(__NO_INTERP)

# Interpreter pointer for callbacks and objects which need a Tcl interpreter.
const __context = [__NO_INTERP for i in 1:Threads.nthreads()]

"""
```julia
__interp()
```

yields the contextual Tcl interpreter of the calling thread.  Beware that this
may be a NULL interpreter.  The contextual Tcl interpreter shall only be used
for error messages and for creating callbacks.

See also: [`__intptr`](@ref), [`__set_context`](@ref),
          [`__reset_context`](@ref).

"""
@inline __interp() =
    # one-line definition does not work as expected...
    (@inbounds interp = __context[Threads.threadid()];
     return interp)

"""
```julia
__intptr()
```

yields a reference to the contextual Tcl interpreter of the calling thread.
Beware that this may be a NULL pointer.  The contextual Tcl interpreter shall
only be used for error messages and for creating callbacks.

See also: [`__interp`](@ref), [`__set_context`](@ref),
          [`__reset_context`](@ref).

"""
@inline __intptr() = __interp().ptr

"""
```julia
__reset_context()
```

resets the context for the calling thread.

See also: [`__interp`](@ref), [`__set_context`](@ref),
          [`__contextual_error`](@ref).

"""
@inline __reset_context() = __set_context(__NO_INTERP)

"""
```julia
__set_context(interp)
```

sets the contextual Tcl interpreter for the calling thread.

See also: [`__interp`](@ref), [`__reset_context`](@ref),
          [`__contextual_error`](@ref).

"""
@inline __set_context(interp::TclInterp) =
    @inbounds __context[Threads.threadid()] = interp

"""
```julia
__contextual_error(msg)
```

throws a Tcl error exception with message retrieved from the contextual
Tcl interpreter of the calling thread, if any, or given by `msg`, otherwise.

See also: [`__set_context`](@ref),  [`__reset_context`](@ref).

"""
__contextual_error(msg::String) =
    (intptr = __intptr();
     (intptr == C_NULL ? msg : __objptr_to(String, Tcl_GetObjResult(intptr))))

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

getresult(::Type{T}, interp::TclInterp) where {T} = __getresult(T, interp)

# Tcl_GetStringResult calls Tcl_GetObjResult, so we only interface to this
# latter function.  Incrementing the reference count of the result is only
# needed if we want to keep a long-term reference to it,
# `__objptr_to(TclObj,...)` takes care of that).
__getresult(::Type{T}, interp::TclInterp) where {T} =
    __objptr_to(T, Tcl_GetObjResult(interp.ptr))


"""
```julia
Tcl.exec([T,][interp,], args...; kwds...)
```

makes a list of the arguments `args...` and keywords `kwds...` and evaluates it
as a Tcl script.  See [`Tcl.eval`](@ref) for details about optional result type
`T` and Tcl interpreter `interp`.

Any specified keyword, say `key=val`, is automatically converted in the pair of
arguments `-key val` in this list (note the hyphen before the keyword name).
To allow for option names that are Julia keywords, a leading underscore is
stripped, if any, in `key`.  All keywords appear at the end of the list in
unspecific order.

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
exec(args...; kwds...) =
    exec(getinterp(), args...; kwds...)

exec(::Type{T}, args...; kwds...) where {T} =
    exec(T, getinterp(), args...; kwds...)

exec(interp::TclInterp, args...; kwds...) =
    exec(Any, interp, args...; kwds...)

function exec(::Type{T}, interp::TclInterp, args...; kwds...) where {T}
    length(args) ≥ 1 || Tcl.error("expecting at least one argument")
    listptr = C_NULL
    __set_context(interp)
    try
        listptr = Tcl_IncrRefCount(__newlistobj())
        @__build_list listptr args kwds
        return __eval(T, interp, TclObj{List}, listptr)
    finally
        listptr == C_NULL || Tcl_DecrRefCount(listptr)
         __reset_context()
    end
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
Tcl.eval(args...) =
    Tcl.eval(getinterp(), args...)

Tcl.eval(::Type{T}, args...) where {T} =
    Tcl.eval(T, getinterp(), args...)

Tcl.eval(interp::TclInterp, args...) =
    Tcl.eval(Any, interp, args...)

function Tcl.eval(::Type{T}, interp::TclInterp,
                  script::Union{AbstractString,Symbol}) where {T}
    return Tcl.eval(T, interp, string(script))
end

function Tcl.eval(::Type{T}, interp::TclInterp, script::String) where {T}
    # A single string (or equivalent) is argument is to be evaluated.
    __set_context(interp)
    try
        return __eval(T, interp, String, script)
    finally
        __reset_context()
    end
end

function Tcl.eval(::Type{T}, interp::TclInterp, script::TclObj{S}) where{T,S}
    # A managed Tcl object is directly evaluated.  This saves the concatenation
    # which produces the same thing. FIXME: check this for a string.
    __set_context(interp)
    try
        return __eval(T, interp, TclObj{S}, __objptr(script))
    finally
        __reset_context()
    end
end

function Tcl.eval(::Type{T}, interp::TclInterp, args...) where {T}
    # Zero or more arguments, or a single non-list and non-string-like argument
    # are to be evaluated.  Concatenate all arguments and evaluate the
    # resulting list.
    length(args) ≥ 1 || Tcl.error("missing script to evaluate")
    listptr = C_NULL
    __set_context(interp)
    try
        listptr = Tcl_IncrRefCount(__newlistobj())
        @__concat_args listptr args
        return __eval(T, interp, TclObj{List}, listptr)
    finally
        listptr == C_NULL || Tcl_DecrRefCount(listptr)
        __reset_context()
    end
end

# Called in a properly set context, this method should produce consistent error
# messages and result of given type T.
function __eval(::Type{T}, interp::TclInterp, ::Type{S}, script) where {T,S}
    if __eval(TclStatus, interp, S, script) != TCL_OK
        Tcl.error(interp)
    end
    return __getresult(T, interp)
end

# For a not well defined Tcl object type, we peek the real object type to
# decide which of `Tcl_EvalObjEx` or `Tcl_EvalObjv` to call.
function __eval(::Type{TclStatus}, interp::TclInterp,
                ::Type{TclObj}, objptr::TclObjPtr)
    return __eval(TclStatus, interp, TclObj{__objtype(objptr)}, objptr)
end

# For a script given as a string, `Tcl_EvalEx` is slightly faster than
# `Tcl_Eval` (says the doc.) and, more importantly, the script may contain
# embedded nulls.
__eval(::Type{TclStatus}, interp::TclInterp, ::Type{String}, script::String) =
    Tcl_EvalEx(interp.ptr, Base.unsafe_convert(Ptr{Cchar}, script),
               sizeof(script), TCL_EVAL_GLOBAL|TCL_EVAL_DIRECT)

# For non-list objects, we use `Tcl_EvalObjEx` to evaluate a single argument
# script.  `Tcl_EvalObjEx` does manage the reference count of its object
# argument.
function __eval(::Type{TclStatus}, interp::TclInterp,
                ::Type{TclObj{S}}, objptr::TclObjPtr) where S
    flags = TCL_EVAL_GLOBAL
    if Tcl_GetRefCount(objptr) < 1
        # For a temporary object there is no needs to compile the script.
        flags |= TCL_EVAL_DIRECT
    end
    return Tcl_EvalObjEx(interp.ptr, objptr, flags)
end

function __eval(::Type{TclStatus}, interp::TclInterp,
                ::Type{TclObj{List}}, listptr::TclObjPtr)
    flags = TCL_EVAL_GLOBAL
    status, objc, objv = Tcl_ListObjGetElements(interp.ptr, listptr)
    if status == TCL_OK
        status = Tcl_EvalObjv(interp.ptr, objc, objv, flags)
    end
    return status
end

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

const __timer = Ref{Timer}()

"""
```julia
Tcl.isrunning()
```

yields whether the processing of Tcl/Tk events is running.

"""
isrunning() = (isdefined(__timer, 1) && isopen(__timer[]))

"""
```julia
Tcl.resume()
```

resumes or starts the processing of Tcl/Tk events.  This manages to repeatedly
call function `Tcl.doevents`.  The method `Tcl.suspend` can be called to
suspend the processing of events.

Calling `Tcl.resume` is mandatory when Tk extension is loaded.  Thus:

```julia
Tcl.eval(interp, "package require Tk")
Tcl.resume()
```

is the recommended way to load Tk package.  Alternatively:

```julia
Tcl.tkstart(interp)
```

can be called to do that.

"""
resume() =
    (isrunning() || (__timer[] = Timer(doevents, 0.1; interval=0.05)); nothing)

"""
```julia
Tcl.suspend()
```

suspends the processing of Tcl/Tk events for all interpreters.  The method
`Tcl.resume` can be called to resume the processing of events.

"""
suspend() =
    (isrunning() && close(__timer[]); nothing)

"""
```julia
Tcl.doevents(flags = TCL_DONT_WAIT|TCL_ALL_EVENTS)
```

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

const __releaseobject_proc = Ref{Ptr{Cvoid}}() # will be set by __init__

__releaseobject(ptr::Ptr{Cvoid}) = release(unsafe_pointer_to_objref(ptr))

const __evalcommand_proc = Ref{Ptr{Cvoid}}() # will be set by __init__

function __evalcommand(fptr::ClientData, iptr::TclInterpPtr,
                       objc::Cint, objv::Ptr{TclObjPtr}) :: Cint
    func = unsafe_pointer_to_objref(fptr)
    interp = TclInterp(iptr) # weak reference
    __set_context(interp) # FIXME: not needed?
    try
        args = __buildvector(objc, objv)
        return __setcommandresult(interp, func(interp, args...))
    catch ex
        setresult(interp, "(callback error) " * geterrmsg(ex))
        return TCL_ERROR
    finally
        __reset_context() # FIXME: not needed?
    end
end

# If the function provides a return code, we do want to return it to the
# interpreter, otherwise TCL_OK is assumed.
__setcommandresult(interp::TclInterp, args...) =
    __setcommandresult(interp, TCL_OK, args...)

__setcommandresult(interp::TclInterp, args::Tuple) =
    __setcommandresult(interp, TCL_OK, args...)

__setcommandresult(interp::TclInterp, args::Tuple{TclStatus,Vararg}) =
    __setcommandresult(interp, args[1], args[2:end]...)

__setcommandresult(interp::TclInterp, status::TclStatus) =
    (Tcl_SetObjResult(interp.ptr, __newobj()); return status)

__setcommandresult(interp::TclInterp, status::TclStatus, arg) =
    (Tcl_SetObjResult(interp.ptr, __newobj(arg)); return status)

__setcommandresult(interp::TclInterp, status::TclStatus, args...) =
    (Tcl_SetObjResult(interp.ptr, __newobj(args)); return status)

# With precompilation, `__init__()` carries on initializations that must occur
# at runtime like `@cfunction` which returns a raw pointer.
function __init__()
    __initial_interpreter[] = TclInterp(true)
    __releaseobject_proc[] = @cfunction(__releaseobject, Cvoid, (Ptr{Cvoid},))
    __evalcommand_proc[] = @cfunction(__evalcommand, Cint,
                                      (ClientData, TclInterpPtr,
                                       Cint, Ptr{TclObjPtr}))
    __init_types()
end

"""
```julia
Tcl.CallBack([interp,] [name,] f) -> name
```

creates a callback command named `name` in Tcl interpreter `interp` (or in the
initial Tcl interpreter if this argument is omitted).  If `name` is missing
`Tcl.autoname("jl_callback")` is used to automatically define a name.  The
command name is returned as a string.  The Tcl command will call the Julia
function `f` as follows:

```julia
f(interp, name, args...) -> [status::TclStatus], vals...
```

where `interp` is the Tcl interpreter which calls the command, `name` is the
command name and `args...` are the arguments of the command.

The function can return any number of values.  The status retuned to the
interpreter by the command is assumed to be the first of these values if its
type is `TclStatus` (one of `TCL_OK`, `TCL_ERROR`, `TCL_RETURN`, `TCL_BREAK` or
`TCL_CONTINUE`); otherwise, `TCL_OK` is assumed.  The other values are stored
in the interpreter's result.

If the function throws any exception, the error message associated with the
exception is stored in the interpreter's result and `TCL_ERROR` is retuned to
the interpreter.

See also: [`Tcl.deletecommand`](@ref), [`Tcl.autoname`](@ref).

"""
Callback(func::Function) =
    Callback(getinterp(), func)

Callback(name::StringOrSymbol, func::Function) =
    Callback(getinterp(), name, func)

Callback(interp::TclInterp, func::Function) =
    __newcallback(interp.ptr,func)

Callback(interp::TclInterp, name::StringOrSymbol, func::Function) =
    __newcallback(interp.ptr, name, func)

__newcallback(func::Function) =
    __newcallback(__intptr(), func)

__newcallback(intptr::TclInterpPtr, func::Function) =
    __newcallback(intptr, autoname("jl_callback"), func)

__newcallback(intptr::TclInterpPtr, name::Symbol, func::Function) =
    __newcallback(intptr, string(name), func)

function __newcallback(intptr::TclInterpPtr, name::String, func::Function)
    local cmd :: TclObj{Function}
    if intptr != C_NULL
        preserve(func)
        token = Tcl_CreateObjCommand(intptr, name, __evalcommand_proc[],
                                     pointer_from_objref(func),
                                     __releaseobject_proc[])
        if token == C_NULL
            release(func)
            Tcl.error(__objptr_to(String, Tcl_GetObjResult(intptr)))
        end
        cmd = TclObj{Function}(__newobj(""))
        Tcl_GetCommandFullName(intptr, token, __objptr(cmd))
    else
        cmd = TclObj{Function}(__newobj(name))
    end
    return Callback(intptr, cmd, func)
end

TclObj(func::Function) = Callback(func)

AtomicType(::Type{<:Union{Function,Callback}}) = Atomic()

__objptr(func::Function) = __objptr(__newobj(func))

__newobj(func::Function) = __objptr(__newcallback(func))

__objptr(func::Callback) = __objptr(func.obj)


"""
```julia
Tcl.deletecommand([interp,] cmd)
```

deletes a command named `cmd` in Tcl interpreter `interp` (or in the initial
Tcl interpreter if this argument is omitted). `cmd` can also be a callback.

See also: [`Tcl.Callback`](@ref).

"""
deletecommand(cmd::Union{StringOrSymbol,Callback}) =
    # Since a callback just has a weak reference to the interpreter where it
    # was created, we must not use it as a default.
    deletecommand(getinterp(), cmd)

deletecommand(interp::TclInterp, cmd::Callback) =
    deletecommand(interp, cmd.name)

function deletecommand(interp::TclInterp, name::StringOrSymbol)
    if Tcl_DeleteCommand(interp.ptr, name) != TCL_OK
        Tcl.error(interp)
    end
    return nothing
end
