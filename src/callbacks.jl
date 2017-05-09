# Implement callbacks.

# Dictionary of objects shared with Tcl to to make sure they are not garbage
# collected until Tcl deletes their reference.
__references = Dict{Any,Int}()

function preserve(obj)
    __references[obj] = getkey(__references, obj, 0) + 1
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

const __releaseobject_ptr = cfunction(__releaseobject, Void, (Ptr{Void}, ))

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

# If the function provides a return code, we do want to returne it to the
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

const __evalcommand_ptr = cfunction(__evalcommand, Cint,
                                    (Ptr{Void}, Ptr{Void}, Cint, Ptr{Cstring}))

"""
       Tcl.createcommand([interp,] name, f) -> name

creates a command named `name` in Tcl interpreter `interp` (or in the global
Tcl interpreter if this argument is omitted).  The string version of `name` is
returned.  The Tcl command will call the Julia function `f` as follows:

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
createcommand(name::Name, f::Function) =
    createcommand(defaultinterpreter(), name, f)

createcommand(interp::TclInterp, name::Symbol, f::Function) =
    createcommand(interp, tclrepr(name), f)

function createcommand(interp::TclInterp, name::String, f::Function)
    # Before creating the command, make sure object is not garbage collected
    # until Tcl deletes its reference.
    preserve(f)
    ptr = ccall((:Tcl_CreateCommand, libtcl), Ptr{Void},
                (TclInterpPtr, Cstring, Ptr{Void}, Ptr{Void}, Ptr{Void}),
                interp.ptr, name, __evalcommand_ptr, pointer_from_objref(f),
                __releaseobject_ptr)
    if ptr == C_NULL
        release(f)
        tclerror(interp)
    end
    return name
end

"""
    Tcl.deletecommand([interp,] name)

deletes a command named `name` in Tcl interpreter `interp` (or in the global
Tcl interpreter if this argument is omitted).

See also: `Tcl.createcommand`
"""
deletecommand(name::Name) = deletecommand(defaultinterpreter(), name)

deletecommand(interp::TclInterp, name::Symbol) =
    deletecommand(interp, tclrepr(name))

function deletecommand(interp::TclInterp, name::String)
    code = ccall((:Tcl_DeleteCommand, libtcl), Cint,
                 (TclInterpPtr, Cstring), interp.ptr, name)
    if code != TCL_OK
        tclerror(interp)
    end
    return nothing
end
