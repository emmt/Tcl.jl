#
# types.jl -
#
# Definitions of Tcl constants and types.
#

"""

`TclStatus` is used to represent a status like `TCL_OK` or `TCL_ERROR` returned
by Tcl functions.

"""
struct TclStatus
    code::Cint
end

# Status codes returned by Tcl functions.
const TCL_OK       = TclStatus(0)
const TCL_ERROR    = TclStatus(1)
const TCL_RETURN   = TclStatus(2)
const TCL_BREAK    = TclStatus(3)
const TCL_CONTINUE = TclStatus(4)

# Flags for settings the result.
const TCL_VOLATILE = convert(Ptr{Void}, 1)
const TCL_STATIC   = convert(Ptr{Void}, 0)
const TCL_DYNAMIC  = convert(Ptr{Void}, 3)

# Flags for Tcl variables.
const TCL_GLOBAL_ONLY    = convert(Cint, 1)
const TCL_NAMESPACE_ONLY = convert(Cint, 2)
const TCL_APPEND_VALUE   = convert(Cint, 4)
const TCL_LIST_ELEMENT   = convert(Cint, 8)
const TCL_LEAVE_ERR_MSG  = convert(Cint, 0x200)

# Flags for Tcl processing events.  Set TCL_DONT_WAIT to not sleep: process
# only events that are ready at the time of the call.  Set TCL_ALL_EVENTS to
# process all kinds of events: equivalent to OR-ing together all of the below
# flags or specifying none of them.
const TCL_DONT_WAIT     = convert(Cint, 1<<1)
const TCL_WINDOW_EVENTS = convert(Cint, 1<<2) # Process window system events.
const TCL_FILE_EVENTS   = convert(Cint, 1<<3) # Process file events.
const TCL_TIMER_EVENTS  = convert(Cint, 1<<4) # Process timer events.
const TCL_IDLE_EVENTS   = convert(Cint, 1<<5) # Process idle callbacks.
const TCL_ALL_EVENTS    = ~TCL_DONT_WAIT      # Process all kinds of events.

# The following values control how blocks are combined into photo images when
# the alpha component of a pixel is not 255, a.k.a. the compositing rule.
const TK_PHOTO_COMPOSITE_OVERLAY = convert(Cint, 0)
const TK_PHOTO_COMPOSITE_SET     = convert(Cint, 1)

# Flags for evaluating scripts/commands.
const TCL_NO_EVAL       = convert(Cint, 0x010000)
const TCL_EVAL_GLOBAL   = convert(Cint, 0x020000)
const TCL_EVAL_DIRECT   = convert(Cint, 0x040000)
const TCL_EVAL_INVOKE   = convert(Cint, 0x080000)
const TCL_CANCEL_UNWIND = convert(Cint, 0x100000)
const TCL_EVAL_NOERR    = convert(Cint, 0x200000)

struct TclError <: Exception
    msg::String
end

Base.showerror(io::IO, ex::TclError) = print(io, "Tcl/Tk error: ", ex.msg)

# Structure to store a pointer to a Tcl interpreter. (Even though the address
# should not be modified, it is mutable because immutable objects cannot be
# finalized.)
const TclInterpPtr = Ptr{Void}
mutable struct TclInterp
    ptr::TclInterpPtr
    TclInterp(ptr::TclInterpPtr) = new(ptr)
end

"""

A `ManagedObject` is a Tcl or Tk object which manages its reference count and
of which a pointer to a Tcl object can be retrieved by the `__objptr` method.

"""
abstract type ManagedObject end

# Structure to store a pointer to a Tcl object. (Even though the address
# should not be modified, it is mutable because immutable objects cannot be
# finalized.)  The constructor will refuse to build a managed Tcl object with
# a NULL address.
const TclObjPtr = Ptr{Void}
mutable struct TclObj{T} <: ManagedObject
    ptr::TclObjPtr
    function TclObj{T}(ptr::TclObjPtr) where {T}
        ptr != C_NULL || __illegal_null_object_pointer()
        obj = new{T}(Tcl_IncrRefCount(ptr))
        finalizer(obj, __finalize)
        return obj
    end
end

struct Callback <: ManagedObject
    intptr::TclInterpPtr # weak reference to interpreter
    obj::TclObj{Function} # command name (possibly fully-qualified)
    func::Function
end

# Tcl wide integer is 64-bit integer.
const WideInt = Int64

# Type used in the signature of a Tcl list object (a.k.a. vector in Julia).
const List = Vector

# Token used by Tcl to identify an object command.
const TclCommand = Ptr{Void}

# Floating-point types.
const FloatingPoint = Union{Irrational,Rational,AbstractFloat}

"""

The abstract type `Trait` is inherited by types indicating specific traits.

See also: [`atomictype`](@ref).

"""
abstract type Trait end

"""

Atomic types are those of values that are considered as single list element.
The *atomic* trait indicates whether a value or an object is atomic or not;
Abstract type `AtomicType` has two concrete singleton sub-types: `Atomic` for
atomic objects and `NonAtomic` for other objects/values.  This trait is used
when concatenating objects or values in lists: atomic objects will be seen as a
single item while non atomic ones will be split in zero, one or several items.

See also: [`atomictype`](@ref), [`Trait`](@ref).

"""
abstract type AtomicType <: Trait end

for T in (:NonAtomic, :Atomic)
    @eval begin
        struct $T <: AtomicType end
        @doc @doc(AtomicType) $T
    end
end

# Client data used by commands and callbacks.
const ClientData = Ptr{Void}

const TclObjList    = TclObj{List}
const TclObjCommand = TclObj{Function}

# `Name` is anything that can be understood as the name of a variable or of a
# command.
const Name = Union{AbstractString,Symbol,TclObj{String}}

# `StringOrSymbol` can be automatically converted into a `Cstring` by `ccall`.
const StringOrSymbol = Union{AbstractString,Symbol}

# A `Byte` is any bits type that is exactly 8 bits.
const Byte = Union{UInt8,Int8}

# Objects of type `Iterables` are considered as iterators, making an object out
# of them yield a Tcl list.
const Iterables = Union{AbstractVector,Tuple,Set,IntSet}

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

Base.show{T<:TkObject}(io::IO, ::MIME"text/plain", w::T) =
    print(io, "$T(\"$(string(w))\")")

Base.show(io::IO, w::TkObject) = print(io, string(w))

Base.string(w::TkObject) = getpath(w)

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

Base.show(io::IO, ::MIME"text/plain", c::T) where {T<:TkGray} =
    print(io, "$T(gray: $(string(gray(c))))")

Base.show(io::IO, ::MIME"text/plain", c::T) where {T<:Union{TkRGB,TkBGR}} =
    print(io, "$T(red: $(string(red(c))), $(string(green(c))), $(string(blue(c))))")

Base.show(io::IO, ::MIME"text/plain", c::T) where {T<:Union{TkRGBA,TkABGR}} =
    print(io, "$T(red: $(string(red(c))), $(string(green(c))), $(string(blue(c))), $(string(alpha(c))))")

Base.show(io::IO, c::TkColor) = print(io, string(c))

Base.string(c::Union{TkRGB{UInt8},TkBGR{UInt8}}) =
    @sprintf("#%02x%02x%02x", red(c), green(c), blue(c))

Base.string(c::Union{TkRGB{UInt16},TkBGR{UInt16}}) =
    @sprintf("#%04x%04x%04x", red(c), green(c), blue(c))

function Base.string(c::TkGray{UInt8})
    s = @sprintf("%02x", gray(c))
    string('#', s, s, s)
end

function Base.string(c::TkGray{UInt16})
    s = @sprintf("%04x", gray(c))
    string('#', s, s, s)
end
