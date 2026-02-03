#
# basics.jl -
#
# Implement interface to Tcl interpreter, evaluation of scripts, callbacks...
#

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
[`tk_start`](@ref) method to load Tk.

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
        script = generate_pre_init_script()
        if Tcl_Eval(interp, script) != TCL_OK
            @warn "Unable to evaluate Tcl pre-initialization script: $(getresult(interp))"
        elseif Tcl_Init(interp) != TCL_OK
            @warn "Unable to initialize Tcl interpreter"
        end
        @info unsafe_string(Tcl_GetVar(interp, "auto_path", TCL_GLOBAL_ONLY))
    catch
        Tcl_DeleteInterp(interp)
        rethrow()
    end
    return _TclInterp(interp) # call inner constructor
end

# NOTE Following to Tcl doc. (read `man 3tcl auto_path`) and to the `init.tcl` script. We
# set global Tcl variable `tcl_library` to be the directory where is the `init.tcl` script
# of the Tcl artifact and the global Tcl variable `env(TCLLIBPATH)` to the ordered list
# (first Tcl, then Tk) of directories where file `pkgIndex.tcl` can be found.
function generate_pre_init_script()
    # Empty script and list of `auto_path` directories.
    script = String[]
    auto_path = String[]
    (major, minor, patch, release) = tcl_version(Tuple)

    # Start with Tcl library.
    tcl_subdir = joinpath("lib", "tcl$(major).$(minor)")
    tcl_library = abspath(Tcl_jll.artifact_dir, tcl_subdir)
    if !isdir(tcl_library)
        @warn "Tcl library directory \"$(tcl_subdir)\" not found in the artifact directory"
    else
        update_auto_path!(auto_path, tcl_library)
        if !isfile(joinpath(tcl_library, "init.tcl"))
            @warn "Tcl \"init.tcl\" not found in sub-directory \"$(tcl_subdir)\" of the artifact directory"
        else
            push!(script, "set tcl_library $(quote_string(tcl_library))")
        end
    end

    # Add Tk library. Global variable `tk_library` will only be set when `Tk` is loaded.
    tk_subdir = joinpath("lib", "tk$(major).$(minor)")
    tk_library = abspath(Tk_jll.artifact_dir, tk_subdir)
    if !isdir(tk_library)
        @warn "Tk library directory \"$(tk_subdir)\" not found in the artifact directory"
    else
        update_auto_path!(auto_path, tk_library)
    end

    # Register the list of directories to initially have in `auto_path` via the global
    # `env(TCLLIBPATH)`.
    if haskey(ENV, "TCLLIBPATH")
        @warn "Environment variable `TCLLIBPATH` must be reset to Tcl/Tk artifact directories"
        delete!(ENV, "TCLLIBPATH")
    end
    push!(script, "set env(TCLLIBPATH) {}")
    for dir in auto_path
        push!(script, "lappend env(TCLLIBPATH) $(quote_string(dir))")
    end

    return join(script, "\n")
end

function update_auto_path!(auto_path::Vector{String}, library::AbstractString)
    isdir(library) || return auto_path
    library ∈ auto_path || push!(auto_path, library)
    isabspath(library) || return auto_path
    parent = dirname(library)
    isdir(parent) || return auto_path
    parent ∈ auto_path || push!(auto_path, parent)
    # Starting at parent directory, e.g. "$(Tcl_jll.artifact_dir)/lib", append any directory
    # where a file `tclIndex` is found and which is not already in the list (nor its
    # parent).
    for dir in search_tclIndex(parent)
        dir ∈ auto_path && continue
        dirname(dir) ∈ auto_path || push!(auto_path, dir)
    end
    return auto_path
end

function search_tclIndex(dirs::AbstractString...)
    list = String[]
    for dir in dirs
        search_tclIndex!(list, abspath(dir))
    end
    return unique!(sort!(list))
end

function search_tclIndex!(list::Vector{String}, dir::AbstractString)
    for name in readdir(dir; sort=false, join=false)
        if name == "tclIndex"
            dir ∈ list || push!(list, dir)
        else
            path = joinpath(dir, name)
            if isdir(path)
                search_tclIndex!(list, path)
            end
        end
    end
    return list
end

# Make a Tcl interpreter callable.
(interp::TclInterp)(::Type{T}, args...; kwds...) where {T} =
    Tcl.eval(T, interp, args...; kwds...)
(interp::TclInterp)(args...; kwds...) = Tcl.eval(interp, args...; kwds...)

Base.show(io::IO, ::MIME"text/plain", interp::TclInterp) = show(io, interp)
function Base.show(io::IO, interp::TclInterp)
    print(io, "Tcl interpreter (address: ")
    show(io, UInt(pointer(interp)))
    print(io, ", threadid: ", interp.threadid, ")")
end

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
        return unsafe_string(Tcl_GetStringResult(interp))
    end
end
function getresult(::Type{T}, interp::TclInterp) where {T}
    GC.@preserve interp begin
        return unsafe_get(T, Tcl_GetObjResult(interp))
    end
end

# Make `interp[]` yield result.
Base.getindex(interp::TclInterp) = getresult(String, interp)

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
        result_ptr = new_object(val) # this may throw
        if true
            # As can be seen in `generic/tclResult.c`, `Tcl_SetObjResult` does manage the
            # reference count of its object argument so it is OK to directly pass a
            # temporary object.
            Tcl_SetObjResult(interp_ptr, result_ptr)
        else
            # A safer approach is to increment the reference count of the temporary object
            # before calling `Tcl_SetObjResult` and decrement it after.
            Tcl_SetObjResult(interp_ptr, Tcl_IncrRefCount(result_ptr))
            Tcl_DecrRefCount(result_ptr)
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
    length(args) ≥ 1 || throw(TclError("expecting at least one argument"))
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
        list_ptr = unsafe_new_list(unsafe_append_list, interp_ptr, args...)
        status = Tcl_EvalObjEx(interp_ptr, Tcl_IncrRefCount(list_ptr),
                               TCL_EVAL_DIRECT | TCL_EVAL_GLOBAL)
        Tcl_DecrRefCount(list_ptr)
        return unsafe_result(T, status, interp_ptr)
    end
end

function unsafe_result(::Type{TclStatus}, status::TclStatus, interp::InterpPtr)
    return status
end

function unsafe_result(::Type{T}, status::TclStatus, interp::InterpPtr) where {T}
    status == TCL_OK && return unsafe_get(T, Tcl_GetObjResult(interp))
    status == TCL_ERROR && unsafe_error(interp)
    throw_unexpected(status)
end
