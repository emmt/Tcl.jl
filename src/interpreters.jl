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
        # Initialize Tcl interpreter to find Tcl library scripts.
        if isdefined(@__MODULE__, :Tcl_jll)
            tcl_library = joinpath(dirname(dirname(Tcl_jll.libtcl_path)), "lib",
                                   "tcl$(TCL_MAJOR_VERSION).$(TCL_MINOR_VERSION)")
            @info "Set `tcl_library` to \"$(tcl_library)\""
            ptr = Tcl_SetVar(interp, "tcl_library", tcl_library, TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
            isnull(ptr) && @warn "Unable to set `tcl_library`: $(unsafe_string_result(interp))"
        end
        status = @ccall libtcl.Tcl_Init(interp::Ptr{Tcl_Interp})::TclStatus
        status == TCL_OK || @warn "Unable to initialize Tcl interpreter: $(unsafe_string_result(interp))"

        # Initialize Tcl interpreter to find Tk library scripts.
        if isdefined(@__MODULE__, :Tk_jll)
            tk_library = joinpath(dirname(dirname(Tk_jll.libtk_path)), "lib",
                                  "tk$(TCL_MAJOR_VERSION).$(TCL_MINOR_VERSION)")
            @info "Set `tk_library` to \"$(tk_library)\""
            ptr = Tcl_SetVar(interp, "tk_library", tk_library, TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
            isnull(ptr) && @warn "Unable to set `tk_library`: $(unsafe_string_result(interp))"
        end
        if TCL_MAJOR_VERSION >= 9
            # In Tcl/Tk 9, library scripts are embedded in the dynamic library via zipfs.
            # Tcl mounts its own zipfs automatically, but we must mount Tk's.
            status = @ccall libtcl.TclZipfs_Mount(
                interp::Ptr{Tcl_Interp}, Tk_jll.libtk_path::Cstring, "//zipfs:/lib/tk"::Cstring,
                C_NULL::Cstring)::TclStatus
            status == TCL_OK || @warn "Unable to mount Tk zipfs: $(unsafe_string_result(interp))"
        end
        status = @ccall libtk.Tk_Init(interp::Ptr{Tcl_Interp})::TclStatus
        status == TCL_OK || @warn "Unable to initialize Tk interpreter: $(unsafe_string(Tcl_GetStringResult(interp)))"
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

Base.show(io::IO, ::MIME"text/plain", interp::TclInterp) = show(io, interp)
function Base.show(io::IO, interp::TclInterp)
    print(io, "Tcl interpreter (address: ")
    show(io, UInt(pointer(interp)))
    print(io, ", threadid: ", interp.threadid, ")")
end

#------------------------------------------------------------------ Interpreter properties -

Base.propertynames(interp::TclInterp) = (:concat, :eval, :exec, :list, :ptr,
                                         :result, :threadid)

@inline Base.getproperty(interp::TclInterp, key::Symbol) = _getproperty(interp, Val(key))
_getproperty(interp::TclInterp, ::Val{:concat}) = PrefixedFunction(concat, interp)
_getproperty(interp::TclInterp, ::Val{:eval}) = PrefixedFunction(Tcl.eval, interp)
_getproperty(interp::TclInterp, ::Val{:exec}) = PrefixedFunction(exec, interp)
_getproperty(interp::TclInterp, ::Val{:list}) = PrefixedFunction(list, interp)
_getproperty(interp::TclInterp, ::Val{:ptr}) = getfield(interp, :ptr)
_getproperty(interp::TclInterp, ::Val{:result}) = PrefixedFunction(getresult, interp)
_getproperty(interp::TclInterp, ::Val{:threadid}) = getfield(interp, :threadid)
_getproperty(interp::TclInterp, ::Val{key}) where {key} = throw(KeyError(key))

# Properties are read-only, only `finalize` (see below) may change their values.
@noinline function Base.setproperty!(interp::TclInterp, key::Symbol, val)
    key ∈ propertynames(interp) || throw(KeyError(key))
    error("attempt to set read-only field `$key` in Tcl interpreter")
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

#---------------------------------------------------------------------- Interpreter result -

"""
    interp[] -> str::String
    interp.result() -> str::String
    Tcl.getresult() -> str::String
    Tcl.getresult(interp) -> str::String

    interp.result(T) -> val::T
    Tcl.getresult(T) -> val::T
    Tcl.getresult(T, interp) -> val::T
    Tcl.getresult(interp, T) -> val::T

Retrieve the result of interpreter `interp` as a value of type `T` or as a string if `T` is
not specified. `Tcl.getresult` returns the result of the shared interpreter of the thread.
`T` may be `TclObj` to retrieve a managed Tcl object.

# See also

[`TclInterp`](@ref) and [`TclObj`](@ref).

"""
getresult() = get(TclInterp())
getresult(::Type{T}) where {T} = getresult(T, TclInterp())
getresult(interp::TclInterp) = getresult(String, interp)

getresult(interp::TclInterp, ::Type{T}) where {T} = getresult(T, interp)

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

# To set Tcl interpreter result, we call `Tcl_SetObjResult` for any object, as
# `Tcl_SetResult` is a macro since Tcl 9.

setresult!(interp::TclInterp, result::TclObj) =
    Tcl_SetObjResult(interp, result)

function setresult!(interp::TclInterp, result)
    # Here we save creating a mutable `TclObj` structure to temporarily wrap the new Tcl
    # object.
    GC.@preserve interp begin
        interp_ptr = checked_pointer(interp) # this may throw
        result_ptr = new_object(result) # this may throw
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

# TODO rename and doc
isdeleted(interp::TclInterp) = isnull(pointer(interp)) || !iszero(Tcl_InterpDeleted(interp))
isactive(interp::TclInterp) = !isnull(pointer(interp)) && !iszero(Tcl_InterpActive(interp))

@deprecate getinterp(args...; kwds...) TclInterp(args...; kwds...)

#------------------------------------------------------------------- Evaluation of scripts -

"""
    Tcl.exec(T=TclObj, interp=TclInterp(), args...) -> res::T
    interp.exec(T=TclObj, args...) -> res::T

Make a list out of the arguments `args...`, evaluate this list as a Tcl command with
interpreter `interp`, and return a value of type `T`. Any `key => val` pair in `args...` is
converted in the pair of arguments `-key` and `val` in the command list (note the hyphen
before the key name).

The evaluation of a Tcl command stores a result (or an error message) in the interpreter and
returns a status. The behavior of `Tcl.exec` depend on the type `T` of the expected result:

* If `T` is `TclStatus`, the status of the evaluation is returned and the command result may
  be retrieved by calling [`Tcl.getresult`](@ref) or via `interp.result(...)`.

* If `T` is `Nothing`, an exception is thrown if the status is not [`TCL_OK`](@ref) and
  `nothing` is returned otherwise (i.e., the result of the command is ignored).

* Otherwise, an exception is thrown if the status is not [`TCL_OK`](@ref) and the result of
  the command is returned as a value of type `T` otherwise.

# See also

See [`Tcl.list`](@ref) for the rules to build a list (apart from the accounting of pairs).

See [`Tcl.eval`](@ref) for another way to evaluate a Tcl script. The difference with
[`Tcl.eval`](@ref) is that each input argument is interpreted as a different *token* of the
Tcl command.

"""
function exec(::Type{T}, interp::TclInterp, args...) where {T}
    GC.@preserve interp begin
        interp_ptr = checked_pointer(interp)
        list_ptr = unsafe_new_list(unsafe_append_exec_arg, interp_ptr, args...)
        status = Tcl_EvalObjEx(interp_ptr, Tcl_IncrRefCount(list_ptr),
                               TCL_EVAL_DIRECT | TCL_EVAL_GLOBAL)
        Tcl_DecrRefCount(list_ptr)
        return unsafe_result(T, status, interp_ptr)
    end
end

# Provide optional leading arguments.
exec(args...) = exec(TclInterp(), args...)
exec(::Type{T}, args...) where {T} = exec(T, TclInterp(), args...)
exec(interp::TclInterp, args...) = exec(TclObj, interp, args...)

# Re-order leading arguments.
exec(interp::TclInterp, ::Type{T}, args...) where {T} = exec(T, interp, args...)

function unsafe_append_exec_arg(interp::InterpPtr, list::ObjPtr, arg)
    unsafe_append_element(interp, list, arg)
    return nothing
end

function unsafe_append_exec_arg(interp::InterpPtr, list::ObjPtr, (key,val)::Pair)
    unsafe_append_element(interp, list, "-"*string(key))
    unsafe_append_element(interp, list, val)
    return nothing
end

"""
    Tcl.eval(T=TclObj, interp=TclInterp(), args...) -> res::T
    interp.eval(T=TclObj, args...) -> res::T
    interp(T=TclObj, args...) -> res::T

Concatenate arguments `args...` into a list, evaluate this list as a Tcl script with
interpreter `interp`, and return a value of type `T`.Any `key => val` pair in `args...` is
converted in the pair of arguments `-key` and `val` in the script list (note the hyphen
before the key name).

The evaluation of a Tcl script stores a result (or an error message) in the interpreter and
returns a status. The behavior of `Tcl.eval` depend on the type `T` of the expected result:

* If `T` is `TclStatus`, the status of the evaluation is returned and the script result may
  be retrieved by calling [`Tcl.getresult`](@ref) or via `interp.result(...)`.

* If `T` is `Nothing`, an exception is thrown if the status is not [`TCL_OK`](@ref) and
  `nothing` is returned otherwise (i.e., the result of the script is ignored).

* Otherwise, an exception is thrown if the status is not [`TCL_OK`](@ref) and the result of
  the script is returned as a value of type `T` otherwise.

# See also

See [`Tcl.concat`](@ref) for the rules to concatenate arguments into a list (apart from the
accounting of pairs).

See [`Tcl.exec`](@ref) for another way to execute a Tcl command where each of `args...` is
considered as a distinct command argument.

"""
Tcl.eval

# Provide optional leading arguments.
Tcl.eval(args...) = Tcl.eval(TclInterp(), args...)
Tcl.eval(::Type{T}, args...) where {T} = Tcl.eval(T, TclInterp(), args...)
Tcl.eval(interp::TclInterp, args...) = Tcl.eval(TclObj, interp, args...)

# Re-order leading arguments.
Tcl.eval(interp::TclInterp, ::Type{T}, args...) where {T} = Tcl.eval(T, interp, args...)

# Evaluate script provided as a (symbolic) string.
function Tcl.eval(::Type{T}, interp::TclInterp, script::FastString) where {T}
    # For a script given as a string, `Tcl_EvalEx` is slightly faster than `Tcl_Eval` (says
    # the doc.) and, more importantly, the script may contain embedded nulls.
    GC.@preserve interp script begin
        interp_ptr = checked_pointer(interp)
        status = Tcl_EvalEx(interp_ptr, script, sizeof(script),
                            TCL_EVAL_DIRECT | TCL_EVAL_GLOBAL)
        return unsafe_result(T, status, interp_ptr)
    end
end
function Tcl.eval(::Type{T}, interp::TclInterp, script::AbstractString) where {T}
    return Tcl.eval(T, interp, string(script))
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
        list_ptr = unsafe_new_list(unsafe_append_eval_arg, interp_ptr, args...)
        status = Tcl_EvalObjEx(interp_ptr, Tcl_IncrRefCount(list_ptr),
                               TCL_EVAL_DIRECT | TCL_EVAL_GLOBAL)
        Tcl_DecrRefCount(list_ptr)
        return unsafe_result(T, status, interp_ptr)
    end
end

function unsafe_append_eval_arg(interp::InterpPtr, list::ObjPtr, arg)
    unsafe_append_list(interp, list, arg)
    return nothing
end

function unsafe_append_eval_arg(interp::InterpPtr, list::ObjPtr, (key,val)::Pair)
    unsafe_append_element(interp, list, "-"*string(key))
    unsafe_append_element(interp, list, val)
    return nothing
end

unsafe_string_result(interp::Union{TclInterp,InterpPtr}) =
    unsafe_string(Tcl_GetStringResult(interp))

function unsafe_result(::Type{TclStatus}, status::TclStatus, interp::InterpPtr)
    return status
end

function unsafe_result(::Type{Nothing}, status::TclStatus, interp::InterpPtr)
    status == TCL_OK && return nothing
    status == TCL_ERROR && unsafe_error(interp)
    throw_unexpected(status)
end

function unsafe_result(::Type{T}, status::TclStatus, interp::InterpPtr) where {T}
    status == TCL_OK && return unsafe_get(T, Tcl_GetObjResult(interp))
    status == TCL_ERROR && unsafe_error(interp)
    throw_unexpected(status)
end
