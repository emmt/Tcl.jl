# Useful methods for the Julia interface to Tcl/Tk.

"""
    tcl_version() -> num::VersionNumber
    tcl_version(Tuple) -> (major, minor, patch, rtype)::NTuple{4,Cint}

Return the full version of the Tcl C library.

"""
function tcl_version()
    major, minor, patch, rtype = tcl_version(Tuple)
    if rtype == TCL_ALPHA_RELEASE
        return VersionNumber(major, minor, patch, ("alpha",))
    elseif rtype == TCL_BETA_RELEASE
        return VersionNumber(major, minor, patch, ("beta",))
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

#-------------------------------------------------------------------------------- Pointers -

Base.pointer(obj::TclObj) = getfield(obj, :ptr)
Base.pointer(interp::TclInterp) = getfield(interp, :ptr)

# The string representation of a Tcl object is owned by Tcl's value manager, so getting a C
# string pointer from this string is always safe unless object pointer is null.
Base.unsafe_convert(::Type{Cstring}, obj::TclObj) = Tcl_GetString(checked_pointer(obj))
Base.unsafe_convert(::Type{ObjPtr}, obj::TclObj) = checked_pointer(obj)
Base.unsafe_convert(::Type{InterpPtr}, interp::TclInterp) = checked_pointer(interp)

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

assert_same_thread(interp::TclInterp) =
    same_thread(interp) ? nothing : throw_thread_mismatch()

same_thread(interp::TclInterp) =
    getfield(interp, :threadid) == Threads.threadid()

@noinline throw_thread_mismatch() = throw(AssertionError(
    "attempt to use a Tcl interpreter in a different thread"))

"""
    Tcl.Private.isnull(ptr) -> bool

Return whether pointer `ptr` is null.

# See also

[`Tcl.Private.null`](@ref).

"""
isnull(ptr::Union{Ptr,Cstring}) = ptr === null(ptr)

"""
    Tcl.Private.null(ptr) -> nullptr
    Tcl.Private.null(typeof(ptr)) -> nullptr

Return a null-pointer of the same type as `ptr`.

# See also

[`Tcl.Private.isnull`](@ref).

"""
null(ptr::Union{Ptr,Cstring}) = null(typeof(ptr))
null(::Type{Ptr{T}}) where {T} = Ptr{T}(0)
null(::Type{Cstring}) = Cstring(C_NULL)

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

function unsafe_memcmp(a, b, nbytes)
    # NOTE `Ptr{UInt8}`, not `Ptr{Cvoid}`, to have it works for `FastString`.
    return @ccall memcmp(a::Ptr{UInt8}, b::Ptr{UInt8}, nbytes::Csize_t)::Cint
end

#---------------------------------------------------------------------------- Quote string -

"""
    Tcl.quote_string(str)

Return string `str` a valid Tcl string surrounded by double quotes that can be directly
inserted in Tcl scripts.

This is similar to `escape_string` but specialized to represent a valid Tcl string
surrounded by double quotes in a script.

"""
function quote_string(str::AbstractString)
    esc = ('"', '{', '}')
    io = IOBuffer()
    print(io, '"')
    for c::AbstractChar in str
        if c ∈ esc
            print(io, '\\', c)
        elseif isascii(c)
            if isprint(c)
                if c == '\\'
                    print(io, "\\\\")
                else
                    print(io, c)
                end
            elseif c == '\0'
                print(io, "\300\200") # see man page of `Tcl_NewStringObj`
            elseif c == '\e'
                print(io, "\\e")
            elseif '\a' <= c <= '\r'
                print(io, '\\', "abtnvfr"[Int(c)-6])
            else
                print(io, "\\x", string(UInt32(c), base = 16, pad = 2))
            end
        elseif !Base.isoverlong(c) && !Base.ismalformed(c) && isprint(c)
            print(io, c)
        else # malformed, overlong, or not printable
            u = bswap(reinterpret(UInt32, c)::UInt32)
            while true
                print(io, "\\x", string(u % UInt8, base = 16, pad = 2))
                (u >>= 8) == 0 && break
            end
        end
    end
    print(io, '"')
    return String(take!(io))
end

#------------------------------------------------------------------------ Automatic names -

"""
    Tcl.Private.auto_name(pfx = "jl_auto_")

Return a unique name with given prefix. The result is a string of the form `pfx#` where `#`
is a unique number.

"""
function auto_name(pfx::AbstractString = "jl_auto_")
    global auto_name_dict
    T = valtype(auto_name_dict)
    n = get(auto_name_dict, pfx, zero(T)) + one(T)
    auto_name_dict[pfx] = n
    return pfx*string(n)
end

const auto_name_dict = Dict{String,UInt64}()

#-------------------------------------------------------------------------- Tcl type names -

"""
    Tcl.Private.unsafe_get_typename(ptr) -> sym::Symbol

Return the symbolic type name of Tcl object pointer `ptr`. The result can be:

- `:null` for a null Tcl object pointer.

- `:string` for an unspecific object type (i.e., null type pointer null).

- `:boolean`, `:booleanString`, `:int`, `:double`, `:wideInt`, `:bignum`, `:bytearray`,
  `:list`, `:bytecode`, etc. for an object with a specific internal representation.

!!! warning
    The function is *unsafe* as `ptr` may be null and otherwise must be valid for the
    duration of the call (i.e., protected form being garbage collected).

""" unsafe_get_typename

# The table of known types is updated while objects of new types are created because seeking
# for an existing type is much faster than creating the mutable `TclObj` structure so the
# overhead is negligible.
const _known_types = Tuple{ObjTypePtr,Symbol}[]

function unsafe_get_typename(objPtr::ObjPtr)
    isnull(objPtr) && return :null # null object pointer
    typePtr = unsafe_load(Ptr{Tcl_Obj_typePtr_type}(objPtr + Tcl_Obj_typePtr_offset))
    return unsafe_get_typename(typePtr)
end

function unsafe_get_typename(typePtr::ObjTypePtr)
    global _known_types
    for (ptr, sym) in _known_types
        ptr == typePtr && return sym
    end
    return unsafe_register_new_typename(typePtr)
end

@noinline function unsafe_register_new_typename(typePtr::ObjTypePtr)
    if isnull(typePtr)
        sym = :string
    else
        # NOTE Type name is a C string at offset 0 of structure `Tcl_ObjType`.
        namePtr = unsafe_load(Ptr{Tcl_ObjType_name_type}(typePtr + Tcl_ObjType_name_offset))
        isnull(namePtr) && unexpected_null("Tcl object type name")
        sym = Symbol(unsafe_string(namePtr))
    end
    push!(_known_types, (typePtr, sym))
    return sym
end

#---------------------------------------------------------------------------------- Errors -

Base.showerror(io::IO, ex::TclError) = print(io, "Tcl/Tk error: ", ex.msg)

"""
    get_error_message(ex)

Return the error message associated with exception `ex`.

"""
get_error_message(ex::Exception) = sprint(io -> showerror(io, ex))

@noinline argument_error(mesg::AbstractString) = throw(ArgumentError(mesg))
@noinline argument_error(arg, args...) = throw(ArgumentError(string(arg, args...)))

@noinline assertion_error(mesg::AbstractString) = throw(AssertionError(mesg))
@noinline assertion_error(arg, args...) = throw(AssertionError(string(arg, args...)))

@noinline unexpected_null(str::AbstractString) = assertion_error("unexpected NULL ", str)

@noinline throw_unexpected(status::TclStatus) =
    throw(TclError("unexpected return status: $status"))

"""
    Tcl.Private.unsafe_error(interp)

Throw a Tcl error with a message stored in the result of `interp`.

!!! warning
    This method is *unsafe*: the interpreter pointer must be non-null and valid during the
    call.

"""
@noinline unsafe_error(interp::InterpPtr) =
    throw(TclError(unsafe_string(Tcl_GetStringResult(interp))))

"""
    Tcl.Private.unsafe_error(interp, mesg)

Throw a Tcl error. If `interp` is a non-null pointer to a Tcl interpreter, the error message
is taken from interpreter's result; otherwise, the error message is `mesg`.

!!! warning
    This method is *unsafe*: if non-null, interpreter pointer must remain valid during the
    call.

# See also

[`Tcl.Private.unsafe_get`](@ref).

"""
@noinline function unsafe_error(interp::InterpPtr, mesg::AbstractString)
    throw(TclError(unsafe_error_message(interp, mesg)))
end

function unsafe_error_message(interp::InterpPtr, mesg::AbstractString)
    if !isnull(interp)
        cstr = Tcl_GetStringResult(interp)
        if !isnull(cstr) && !iszero(unsafe_load(Ptr{UInt8}(cstr)))
            return unsafe_string(cstr)
        end
    end
    return String(mesg)
end
