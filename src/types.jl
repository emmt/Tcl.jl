#
# types.jl -
#
# Definitions of Tcl constants and types.
#

const InterpPtr = Ptr{Glue.Tcl_Interp}
const ObjTypePtr = Ptr{Glue.Tcl_ObjType}
const ObjPtr = Ptr{Glue.Tcl_Obj}

#@assert Glue.Tcl_Obj_typePtr_type === Glue.Tcl_ObjType

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
        isnull(ptr) || Glue.Tcl_Preserve(ptr)
        interp = new(ptr, Threads.threadid())
        return finalizer(finalize, interp)
    end
end

"""
    ManagedObject

Abstract super-type of Tcl or Tk objects which manage their reference count.

"""
abstract type ManagedObject end

# Structure to store a pointer to a Tcl object. (Even though the address
# should not be modified, it is mutable because immutable objects cannot be
# finalized.)  The constructor will refuse to build a managed Tcl object with
# a NULL address.
mutable struct TclObj <: ManagedObject
    ptr::ObjPtr
    global _TclObj
    function _TclObj(ptr::ObjPtr)
        if !isnull(ptr)
            _ = unsafe_get_typename(ptr) # register object's type
            unsafe_incr_refcnt(ptr)
        end
        return finalizer(finalize, new(ptr))
    end
end

struct Callback <: ManagedObject
    intptr::InterpPtr # weak reference to interpreter
    obj::TclObj # command name (possibly fully-qualified)
    func::Function
end

# Floating-point types.
const FloatingPoint = Union{Irrational,Rational,AbstractFloat}

struct PrefixedFunction{F,T}
    func::F
    arg1::T
end
(f::PrefixedFunction)(args...; kwds...) = f.func(f.arg1, args...; kwds...)

"""

The abstract type `Trait` is inherited by types indicating specific traits.

See also: [`Tcl.AtomicType`](@ref).

"""
abstract type Trait end

# Define the `AtomicType` trait and its 2 singleton sub-types `Atomic` and
# `NonAtomic`.
abstract type AtomicType <: Trait end
for T in (:NonAtomic, :Atomic)
    @eval begin
        struct $T <: AtomicType end
        @doc @doc(AtomicType) $T
    end
end

# FIXME const TclObjCommand = TclObj{Function}

# `Name` is anything that can be understood as the name of a variable or of a
# command.
const Name = Union{AbstractString,Symbol,TclObj}

# Union of types that can be converted into a `Cstring` by `ccall` without overheads.
const FastString = Union{AbstractString,Symbol}

# FIXME # A `Byte` is any bits type that is exactly 8 bits.
# FIXME const Byte = Union{UInt8,Int8}

# FIXME # Objects of type `Iterables` are considered as iterators, making an object out
# FIXME # of them yield a Tcl list.
# FIXME const Iterables = Union{AbstractVector,Tuple,Set,BitSet}

#------------------------------------------------------------------------------
# Tk widgets and other Tk objects.

abstract type TkObject     <: ManagedObject end
abstract type TkWidget     <: TkObject      end
abstract type TkRootWidget <: TkWidget      end

# An image is parameterized by the image type (capitalized).
mutable struct TkImage{T} <: TkObject
    interp::TclInterp
    path::String
end

# We want to have the object type and path both printed in the REPL but want
# only the object path with the `string` method or for string interpolation.
# Note that: "$w" calls `string(w)` while "anything $w" calls `show(io, w)`.

Base.show(io::IO, ::MIME"text/plain", w::T) where {T<:TkObject} =
    print(io, "$T(\"$(string(w))\")")

Base.show(io::IO, w::TkObject) = print(io, getpath(w))

#------------------------------------------------------------------------------
# Colors

abstract type TkColor end

struct TkGray{T} <: TkColor
    gray::T
end

struct TkRGB{T} <: TkColor
    r::T; g::T; b::T
end

struct TkBGR{T} <: TkColor
    b::T; g::T; r::T
end

struct TkRGBA{T} <: TkColor
    r::T; g::T; b::T; a::T
end

struct TkBGRA{T} <: TkColor
    b::T; g::T; r::T; a::T
end

struct TkARGB{T} <: TkColor
    a::T; r::T; g::T; b::T
end

struct TkABGR{T} <: TkColor
    a::T; b::T; g::T; r::T
end

const TkColorsWithAlpha{T} = Union{TkRGBA{T},TkBGRA{T},TkARGB{T},TkABGR{T}}
const TkColors{T} = Union{TkRGB{T},TkBGR{T},TkColorsWithAlpha{T}}

gray(c::TkGray{T}) where T = c.gray
red(c::TkColors{T}) where T = c.r
green(c::TkColors{T}) where T = c.g
blue(c::TkColors{T}) where T = c.b
alpha(c::TkColorsWithAlpha{T}) where T = c.a

Base.show(io::IO, ::MIME"text/plain", c::TkGray{T}) where {T} =
    print(io,"TkGray{",T,"}(",gray(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkRGB{T}) where {T} =
    print(io,"TkRGB{",T,"}(",red(c),",",green(c),",",blue(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkBGR{T}) where {T} =
    print(io,"TkRGB{",T,"}(",blue(c),",",green(c),",",red(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkRGBA{T}) where {T} =
    print(io,"TkRGBA{",T,"}(",red(c),",",green(c),",",blue(c),",",alpha(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkBGRA{T}) where {T} =
    print(io,"TkRGBA{",T,"}(",blue(c),",",green(c),",",red(c),",",alpha(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkARGB{T}) where {T} =
    print(io,"TkARGB{",T,"}(",alpha(c),",",red(c),",",green(c),",",blue(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkABGR{T}) where {T} =
    print(io,"TkARGB{",T,"}(",alpha(c),",",blue(c),",",green(c),",",red(c),")")

# Extend Base.show for passing colors to Tk (the alpha component, if any, is
# ignored).
Base.show(io::IO, c::TkGray{T}) where {T<:Union{UInt8,UInt16}} =
    (s = _hex(gray(c)); print(io, "#", s, s, s))
Base.show(io::IO, c::TkColors{T}) where {T<:Union{UInt8,UInt16}} =
    print(io, "#", _hex(red(c)), _hex(green(c)), _hex(blue(c)))
Base.show(io::IO, c::TkColors{T}) where {T<:Union{UInt32,UInt64}} =
    print(io, "#", _hex16(red(c)), _hex16(green(c)), _hex16(blue(c)))

_hex(x::UInt8)  = string(x; base=16, pad=2)
_hex(x::UInt16) = string(x; base=16, pad=4)
_hex(x::UInt32) = string(x; base=16, pad=8)
_hex(x::UInt64) = string(x; base=16, pad=16)
_hex16(x::UInt32) = _hex((x >> 16)%UInt16)
_hex16(x::UInt64) = _hex((x >> 48)%UInt16)
