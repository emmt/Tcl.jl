#
# basics.jl -
#
# Implement interface to Tcl interpreter, evaluation of scripts, callbacks...
#


# For a Tcl object, a valid pointer is simply non-null.
checked_pointer(obj::TclObj) = nonnull_pointer(obj)

# For a Tcl interpreter, a valid pointer is non-null and the interpreter must also live in
# the same thread as the caller.
function checked_pointer(interp::TclInterp)
    ptr = nonnull_pointer(interp)
    assert_same_thread(interp)
    return ptr
end

# For an optional Tcl interpreter, a valid pointer may be null, otherwise the interpreter
# must live in the same thread as the caller.
function null_or_checked_pointer(interp::TclInterp)
    ptr = pointer(interp)
    isnull(ptr) || assert_same_thread(interp)
    return ptr
end

nonnull_pointer(obj) = nonnull_pointer(pointer(obj))
nonnull_pointer(ptr::Ptr) = isnull(ptr) ? throw_null_pointer(ptr) : ptr

assert_nonnull(ptr::Ptr) = isnull(ptr) ? throw_null_pointer(ptr) : nothing

@noinline throw_null_pointer(ptr::Ptr) = throw_null_pointer(typeof(ptr))
@noinline throw_null_pointer(::Type{InterpPtr}) =
    throw(ArgumentError("invalid NULL pointer to Tcl interpreter"))
@noinline throw_null_pointer(::Type{ObjPtr}) =
    throw(ArgumentError("invalid NULL pointer to Tcl object"))
@noinline throw_null_pointer(::Type{Ptr{T}}) where {T} =
    throw(ArgumentError("invalid NULL pointer to object of type `$T`"))

"""
    tcl_version() -> vnum::VersionNumber
    tcl_version(Tuple) -> (major, minor, patch, rtype)::NTuple{4,Cint}

Return the full version of the Tcl C library.

"""
function tcl_version()
    major, minor, patch, rtype = tcl_version(Tuple)
    if rtype == TCL_ALPHA_RELEASE
        return VersionNumber(major, minor, patch, ("beta",))
    elseif rtype == TCL_BETA_RELEASE
        return VersionNumber(major, minor, patch, ("alpha",))
    elseif rtype != TCL_FINAL_RELEASE
        @warn "unknown Tcl release type $rtype"
    end
    return VersionNumber(major, minor, patch)
end

function tcl_version(::Type{Tuple})
    major = Ref{Cint}()
    minor = Ref{Cint}()
    patch = Ref{Cint}()
    rtype = Ref{Cint}()
    Tcl_GetVersion(major, minor, patch, rtype)
    return (major[], minor[], patch[], rtype[])
end

"""
    tcl_library(; relative::Bool=false) -> dir

Return the Tcl library directory as inferred from the installation of the Tcl artifact. If
keyword `relative` is `true`, the path relative to the artifact directory is returned;
otherwise, the absolute path is returned.

The Tcl library directory contains a library of Tcl scripts, such as those used for
auto-loading. It is also given by the global variable `"tcl_library"` which can be retrieved
by:

    interp[:tcl_library] -> dir
    Tcl.getvar(String, interp = TclInterp(), :tcl_library) -> dir

"""
function tcl_library(; relative::Bool=false)
    major, minor, patch, rtype = tcl_version(Tuple)
    path = joinpath("lib", "tcl$(major).$(minor)")
    relative && return path
    return joinpath(Tcl_jll.artifact_dir, path)
end

#=
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
=#

#---------------------------------------------------------- Management of Tcl interpreters -

"""
    interp = TclInterp()
    interp = TclInterp(:shared | :private)

Return a Tcl interpreter. If argument is `:shared` or unspecified, an interpreter shared by
all tasks running on the current thread is returned. If argument is `:private`, a new
private interpreter is created.

!!! warning
    A Tcl interpreter can only be used by the thread where it was created.

The resulting object can be used as a function to evaluate a Tcl script. For example:

```julia
interp("set x 42")
```

yields the result of the script (here the string `"42"`). Command arguments can also be
provide separately:

```
interp("set", "x", 42)
```

yields the value `42` (as an integer). See method [`Tcl.eval`](@ref) for more details
about script evaluation.

The `interp` object can also be indexed as an array to access global Tcl variables (the
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
[`tkstart`](@ref) method to load Tk.

"""
TclInterp(sym::Symbol) =
    sym === :shared ? TclInterp() :
    sym === :private ? _TclInterp() :
    throw(ArgumentError("unexpected argument, shall be `:shared` or `:private`"))

# Create a thread-wise shared interpreter.
function TclInterp()
    global _shared_interpreters
    threadid = Threads.threadid()
    if isassigned(_shared_interpreters, threadid)
        # A shared interpreter already exists for this thread, just return it.
        return @inbounds(_shared_interpreters[threadid])
    else
        # A new interpreter must be created. Call a separate (not in-lined) function so that
        # `TclInterp()` remains small and can be in-lined.
        return _new_shared_interpreter()
    end
end

# Private list of shared Tcl interpreters (one for each thread) created on demand.
const _shared_interpreters = TclInterp[]

@noinline function _new_shared_interpreter()
    global _shared_interpreters
    threadid = Threads.threadid()
    length(_shared_interpreters) < threadid && resize!(_shared_interpreters,
                                                       max(threadid, Threads.nthreads()))
    isassigned(_shared_interpreters, threadid) && throw(AssertionError(
        "there is already a shared Tcl interpreter for this thread ($threadid)"))
    interp = _TclInterp()
    _shared_interpreters[threadid] = interp
    return interp
end

# Create a new Tcl interpreter object.
function _TclInterp()
    interp = Tcl_CreateInterp()
    isnull(interp) && throw(TclError("unable to create Tcl interpreter"))
    try
        # Set Tcl global variable `tcl_library` to the directory where is the "init.tcl" script
        # and evaluate this script.
        library = tcl_library()
        if !isfile(joinpath(library, "init.tcl"))
            dir = tcl_library(; relative=true)
            @warn "Tcl \"init.tcl\" not found in sub-directory \"$dir\" of the artifact"
        elseif Tcl_Eval(interp, "set tcl_library {$(library)}") != TCL_OK
            @warn "unable to set global Tcl variable \"tcl_library\""
        elseif Tcl_Init(interp) != TCL_OK
            @warn "unable to initialize Tcl interpreter"
        end
    catch
        Tcl_DeleteInterp(interp)
        rethrow()
    end
    return _TclInterp(interp) # call inner constructor
end

# Make a Tcl interpreter callable.

(interp::TclInterp)(::Type{T}, args...; kwds...) where {T} =
    Tcl.eval(T, interp, args...; kwds...)

(interp::TclInterp)(args...; kwds...) = Tcl.eval(interp, args...; kwds...)

Base.pointer(interp::TclInterp) = getfield(interp, :ptr)
Base.unsafe_convert(::Type{InterpPtr}, interp::TclInterp) = checked_pointer(interp)

assert_same_thread(interp::TclInterp) =
    same_thread(interp) ? nothing : throw_thread_mismatch()

same_thread(interp::TclInterp) =
    getfield(interp, :threadid) == Threads.threadid()

@noinline throw_thread_mismatch() = throw(AssertionError(
    "attempt to use a Tcl interpreter in a different thread"))

"""
    interp[] -> str::String
    Tcl.getresult() -> str::String
    Tcl.getresult(interp) -> str::String

    Tcl.getresult(T) -> val::T
    Tcl.getresult(T, interp) -> val::T

Retrieve the result of interpreter `interp` as a value of type `T` or as a string if `T` is
not specified. `Tcl.getresult` returns the result of the shared interpreter of the thread.
`T` may be `TclObj` to retrieve a managed Tcl object.

# See also

[`TclInterp`](@ref) and [`TclObj`](@ref).

"""
getresult() = get(TclInterp())
getresult(::Type{T}) where {T} = getresult(T, TclInterp())

getresult(interp::TclInterp) = get(String, interp)
function getresult(::Type{String}, interp::TclInterp)
    GC.@preserve interp begin
        return unsafe_string(unsafe_cstring_result(checked_pointer(interp)))
    end
end
function getresult(::Type{T}, interp::TclInterp) where {T}
    GC.@preserve interp begin
        return unsafe_get(T, unsafe_object_result(checked_pointer(interp)))
    end
end

# Make `interp[]` yield result.
Base.getindex(interp::TclInterp) = getresult(String, interp)

# Interpreter's result. Unsafe: the returned pointer is only valid if the interpreter is
# not deleted.
unsafe_object_result(interp::Union{TclInterp,InterpPtr}) = Tcl_GetObjResult(interp)
unsafe_cstring_result(interp::Union{TclInterp,InterpPtr}) = Tcl_GetStringResult(interp)

"""
    Tcl.setresult!(interp = TclInterp(), val) -> nothing

Set the result stored in Tcl interpreter `interp` with `val`.

If not specified, `interp` is the shared interpreter of the calling thread.

"""
setresult!(val) = setresult!(TclInterp(), val)

# To set Tcl interpreter result, we can call `Tcl_SetObjResult` for any object, or
# `Tcl_SetResult` for string results with no embedded nulls. Julia strings are immutable but
# are volatile. Not sure whether symbols are volatile or not. In doubt, we always use
# `TCL_VOLATILE`.

setresult!(interp::TclInterp, val::FastString) =
    Tcl_SetResult(interp, val, TCL_VOLATILE)

setresult!(interp::TclInterp, val::TclObj) =
    Tcl_SetObjResult(interp, val)

function setresult!(interp::TclInterp, val)
    # Here we save creating a mutable `TclObj` structure to temporarily wrap the new Tcl
    # object.
    GC.@preserve interp begin
        interp_ptr = checked_pointer(interp) # this may throw
        result_ptr = new_object_object(val) # this may throw
        if true
            # As can be seen in `generic/tclResult.c`, `Tcl_SetObjResult` does manage the
            # reference count of its object argument so it is OK to directly pass a
            # temporary object.
            Tcl_SetObjResult(interp_ptr, result_ptr)
        else
            # A safer approach is to increment the reference count of the temporary object
            # before calling `Tcl_SetObjResult` and decrement it after.
            Tcl_SetObjResult(interp_ptr, unsafe_incr_refcnt(result_ptr))
            unsafe_decr_refcnt(result_ptr)
        end
    end
    return nothing
end

function finalize(interp::TclInterp)
    if !same_thread(interp)
        @warn "`finalize` called by wrong thread for Tcl interpreter"
    else
        ptr = pointer(interp)
        if !isnull(ptr)
            setfield!(interp, :ptr, null(ptr)) # we do not want to free more than once
            setfield!(interp, :threadid, 0) # make this interpreter is no longer usable
            Tcl_DeleteInterp(ptr)
            Tcl_Release(ptr)
        end
    end
    return nothing
end

# TODO rename and doc
isdeleted(interp::TclInterp) = isnull(pointer(interp)) || !iszero(Tcl_InterpDeleted(interp))
isactive(interp::TclInterp) = !isnull(pointer(interp)) && !iszero(Tcl_InterpActive(interp))

@deprecate getinterp(args...; kwds...) TclInterp(args...; kwds...)


#------------------------------------------------------------------------------
# Evaluation of Tcl scripts.

#=

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

Apart from the accounting of keywords, the main difference with
[`Tcl.eval`](@ref) is that each input argument is interpreted as a different
*word* of the Tcl script.  Using [`Tcl.eval`](@ref), [`Tcl.exec`](@ref) is
equivalent to:

```julia
Tcl.eval([T,][interp,], Tcl.list(args...; kwds...))
```

Specify `T` as [`TclStatus`](@ref), if you want to avoid throwing errors and
call [`Tcl.getresult`](@ref) to retrieve the result.

See also: [`Tcl.eval`](@ref), [`Tcl.list`](@ref), [`Tcl.getresult`](@ref).

"""
exec(args...; kwds...) =
    exec(TclInterp(), args...; kwds...)

exec(::Type{T}, args...; kwds...) where {T} =
    exec(T, TclInterp(), args...; kwds...)

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
=#

"""
    Tcl.eval([T,][interp,], args...) -> res::Union{T,TclStatus}
    interp([T,] args...) -> res::Union{T,TclStatus}

Concatenate arguments `args...` into a list and evaluates it as a Tcl script with
interpreter `interp` (or in the shared interpreter of the thread if this argument is
omitted). See [`Tcl.concat`](@ref) for details about how arguments are concatenated into a
list.

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
Tcl.eval

# Provide missing leading arguments.
Tcl.eval(args...) = Tcl.eval(TclInterp(), args...)
Tcl.eval(::Type{T}, args...) where {T} = Tcl.eval(T, TclInterp(), args...)
Tcl.eval(interp::TclInterp, args...) = Tcl.eval(TclObj, interp, args...)

function Tcl.eval(::Type{T}, interp::TclInterp) where {T}
    throw(ArgumentError("missing script to evaluate"))
end

# Evaluate script provided as a string.
function Tcl.eval(::Type{T}, interp::TclInterp, script::AbstractString) where {T}
    return Tcl.eval(T, interp, string(script))
end
function Tcl.eval(::Type{T}, interp::TclInterp, script::String) where {T}
    # For a script given as a string, `Tcl_EvalEx` is slightly faster than `Tcl_Eval` (says
    # the doc.) and, more importantly, the script may contain embedded nulls.
    GC.@preserve interp script begin
        interp_ptr = checked_pointer(interp)
        status = Tcl_EvalEx(interp_ptr, pointer(script), ncodeunits(script),
                                 TCL_EVAL_DIRECT | TCL_EVAL_GLOBAL)
        return unsafe_result(T, status, interp_ptr)
    end
end

# Evaluate script provided as a Tcl object.
function Tcl.eval(::Type{T}, interp::TclInterp, script::TclObj) where {T}
    GC.@preserve interp script begin
        interp_ptr = checked_pointer(interp)
        status = Tcl_EvalObjEx(interp_ptr, script,
                                    TCL_EVAL_DIRECT | TCL_EVAL_GLOBAL)
        return unsafe_result(T, status, interp_ptr)
    end
end

# Evaluate script provided as more than one arguments. Concatenate arguments in a Tcl list
# object. Then, call `Tcl_EvalObjEx` which do manage the reference count of its object
# argument.
function Tcl.eval(::Type{T}, interp::TclInterp, args...) where {T}
    GC.@preserve interp begin
        interp_ptr = checked_pointer(interp)
        list_ptr = new_list(unsafe_append_list, interp_ptr, args...)
        status = Tcl_EvalObjEx(interp_ptr, unsafe_incr_refcnt(list_ptr),
                                    TCL_EVAL_DIRECT | TCL_EVAL_GLOBAL)
        unsafe_decr_refcnt(list_ptr)
        return unsafe_result(T, status, interp_ptr)
    end
end

function unsafe_result(::Type{TclStatus}, status::TclStatus, interp::InterpPtr)
    return status
end

function unsafe_result(::Type{T}, status::TclStatus, interp::InterpPtr) where {T}
    status == TCL_OK && return unsafe_get(T, unsafe_object_result(interp))
    status == TCL_ERROR && unsafe_throw_error(interp)
    throw_unexpected(status)
end

@noinline throw_unexpected(status::TclStatus) =
    throw(TclError("unexpected return status: $status"))

@noinline unsafe_throw_error(interp::InterpPtr) =
    throw(TclError(unsafe_string(unsafe_cstring_result(interp))))


#=

#------------------------------------------------------------------------------
# Exceptions

"""
```julia
Tcl.error(arg)
```

throws a [`TclError`](@ref) exception, argument `arg` can be the error message
as a string or a Tcl interpreter (in which case the error message is assumed to
be the current result of the Tcl interpreter).

"""
Tcl.error(msg::AbstractString) = throw(TclError(string(msg)))
Tcl.error(interp::TclInterp) = Tcl.error(getresult(String, interp))

"""
```julia
geterrmsg(ex)
```

yields the error message associated with exception `ex`.

"""
geterrmsg(ex::Exception) = sprint(io -> showerror(io, ex))

#------------------------------------------------------------------------------
# Processing Tcl/Tk events.  The function `do_events` must be repeatedly
# called to process events when Tk is loaded.

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
Tcl.resume(sec=0.05)
```

resumes or starts the processing of Tcl/Tk events with an interval of `sec`
seconds.  This manages to repeatedly call function `Tcl.do_events`.  The method
`Tcl.suspend` can be called to suspend the processing of events.

Calling `Tcl.resume` is mandatory when Tk extension is loaded.  Thus:

```julia
Tcl.eval(interp, "package require Tk")
Tcl.resume()
```

is the recommended way to load Tk package.  Alternatively:

```julia
Tcl.tkstart()
```

can be called to do that.

"""
resume(sec::Real=0.05) =
    (isrunning() || (__timer[] = Timer(do_events, 0.1; interval=sec)); nothing)

"""
```julia
Tcl.suspend()
```

suspends the processing of Tcl/Tk events for all interpreters.  The method
[`Tcl.resume`](@ref) can be called to resume the processing of events.

"""
suspend() =
    (isrunning() && close(__timer[]); nothing)

"""
    Tcl.do_events(flags = TCL_DONT_WAIT|TCL_ALL_EVENTS) -> nevents

Process Tcl/Tk events for all interpreters by calling [`Tcl.do_one_event(flags)`](@ref)
until there are no events matching `flags` and return the number of processed events.
Normally this is automatically called by the timer set by [`Tcl.resume`](@ref).

"""
do_events(::Timer) = do_events()

function do_events(flags::Integer = default_event_flags)
    nevents = 0
    while do_one_event(flags)
        nevents += 1
    end
    return nevents
end

@deprecate doevents(args...; kwds...) do_events(args...; kwds...)

const default_event_flags = TCL_DONT_WAIT|TCL_ALL_EVENTS

"""
    Tcl.do_one_event(flags = TCL_DONT_WAIT|TCL_ALL_EVENTS) -> bool

Process at most one Tcl/Tk event for all interpreters matching `flags` and return whether
one such event was processed. This function is called by [`Tcl.do_events`](@ref).

"""
do_one_event(flags::Integer = default_event_flags) =
    !iszero(Tcl_DoOneEvent(flags))


AtomicType(::Type{<:Union{Function,Callback}}) = Atomic()

__objptr(func::Function) = __objptr(__newobj(func))

__newobj(func::Function) = __objptr(__newcallback(func))

__objptr(func::Callback) = __objptr(func.obj)


=#
