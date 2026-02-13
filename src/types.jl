#
# types.jl -
#
# Definitions of Tcl constants and types.
#

const InterpPtr = Ptr{Tcl_Interp}
const ObjTypePtr = Ptr{Tcl_ObjType}
const ObjPtr = Ptr{Tcl_Obj}

#@assert Tcl_Obj_typePtr_type === Tcl_ObjType

struct TclError <: Exception
    msg::String
end

# Structure to store a pointer to a Tcl interpreter. (Even though the address should not be
# modified, it is mutable because immutable objects cannot be finalized.)
mutable struct TclInterp
    ptr::InterpPtr
    threadid::Int
    global _TclInterp # private inner constructor
    function _TclInterp(ptr::InterpPtr)
        isnull(ptr) || Tcl_Preserve(ptr)
        interp = new(ptr, Threads.threadid())
        return finalizer(finalize, interp)
    end
end

"""
    WrappedObject

Abstract super-type of Julia objects that reflect or wrap a Tcl object.

Such objects implement [`Tcl.Impl.get_objptr`](@ref) to yield a pointer to their
associated Tcl object.

"""
abstract type WrappedObject end

# Structure to store a pointer to a Tcl object. (Even though the address should not be
# modified, it is mutable because immutable objects cannot be finalized.) The constructor
# will refuse to build a managed Tcl object with a NULL address.
mutable struct TclObj <: WrappedObject
    ptr::ObjPtr
    global _TclObj
    function _TclObj(ptr::ObjPtr)
        if !isnull(ptr)
            _ = unsafe_get_typename(ptr) # register object's type
            Tcl_IncrRefCount(ptr)
        end
        return finalizer(finalize, new(ptr))
    end
end

# `Callback` must be mutable to have a stable address given by `pointer_from_objref`.
mutable struct Callback{F<:Function}
    interp::TclInterp
    token::Tcl_Command
    func::F
end

# Floating-point types.
const FloatingPoint = Union{Irrational,Rational,AbstractFloat}

struct PrefixedFunction{F,T}
    func::F
    arg1::T
end
(f::PrefixedFunction)(args...; kwds...) = f.func(f.arg1, args...; kwds...)

# `Name` is anything that can be understood as the name of a variable or of a
# command.
const Name = Union{AbstractString,Symbol,TclObj}

"""
    Tcl.Impl.FastString

Union of types of objects that can be converted into an UTF-8 `Cstring` by `ccall` without
overheads. More specifically, for an instance `str` of this union, the following hold:

* `Base.unsafe_convert(Cstring, str)` is applicable and fast.

* `Base.unsafe_convert(Ptr{UInt8}, str)` and `sizeof(str)` are applicable and respectively
  give the address of the first byte of `str` and the number of bytes in `str`.

"""
const FastString = Union{String,SubString{String},Symbol}

# Union of types for which `string(x...)` is faster than writing in an `IOBuffer` or calling
# `sprint`.
const FasterString = Union{#=Char,=# String, SubString{String}, Symbol}

#-------------------------------------------------------------------------------------------
# Tk widgets and other Tk objects.

abstract type TkWidget     <: WrappedObject end
abstract type TkRootWidget <: TkWidget      end

# An image is parameterized by the symbolic image type.
struct TkImage{T} <: WrappedObject
    interp::TclInterp
    name::TclObj
    function TkImage(::Val{T}, interp::TclInterp, name::TclObj) where {T}
        T isa Symbol || argument_error("image type must be a symbol")
        return new{T}(interp, name)
    end
end

"""
    TkBitmap(args...) -> img
    TkImage{:bitmap}(args...) -> img

Return a Tk *bitmap* image. See [`TkImage`](@ref) for more information.

"""
const TkBitmap = TkImage{:bitmap}

"""
    TkPhoto(args...) -> img
    TkImage{:photo}(args...) -> img

Return a Tk *photo* image. See [`TkImage`](@ref) for more information.

"""
const TkPhoto  = TkImage{:photo}

"""
    TkPixmap(args...) -> img
    TkImage{:pixmap}(args...) -> img

Return a Tk *pixmap* image. See [`TkImage`](@ref) for more information.

"""
const TkPixmap = TkImage{:pixmap}

# Alias for specifying an index range in an image/array view.
const ViewRange{T<:Integer} = Union{Colon,AbstractUnitRange{<:T}}
