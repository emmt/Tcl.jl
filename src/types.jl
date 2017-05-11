# Definitions of Tcl constants and types.

# An empty string is an alias for `nothing`.
const NOTHING = ""

# Codes returned by Tcl fucntions.
const TCL_OK       = convert(Cint, 0)
const TCL_ERROR    = convert(Cint, 1)
const TCL_RETURN   = convert(Cint, 2)
const TCL_BREAK    = convert(Cint, 3)
const TCL_CONTINUE = convert(Cint, 4)

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

# Argument types.
typealias Name      Union{AbstractString,Symbol}
typealias Value     Union{Name,Real}
typealias AnyFloat  Union{AbstractFloat,Irrational,Rational}

# The following type aliases are introduced to make the code more readable.
typealias TclInterpPtr  Ptr{Void}
typealias TclObjPtr     Ptr{Void}
typealias TclObjTypePtr Ptr{Void}

immutable TclError <: Exception
    msg::String
end

Base.showerror(io::IO, ex::TclError) = print(io, "Tcl/Tk error: ", ex.msg)

# Structure to store a pointer to a Tcl interpreter. (Even though the address
# should not be modified, it is mutable because immutable objects cannot be
# finalized.)
type TclInterp
    ptr::TclInterpPtr
    TclInterp(ptr::TclInterpPtr) = new(ptr)
end

# Manage to make any Tcl interpreter usable as a collection with respect to its
# global variables.

Base.getindex(interp::TclInterp, key) = getvar(interp, key)
Base.setindex!(interp::TclInterp, value, key) = setvar(interp, key, value)
Base.haskey(interp::TclInterp, key) = exists(interp, key)

# Structure to store a pointer to a Tcl object. (Even though the address
# should not be modified, it is mutable because immutable objects cannot be
# finalized.)
type TclObj{T}
    ptr::TclObjPtr
    function TclObj(ptr::TclObjPtr)
        @assert ptr != C_NULL # Refuse to build a NULL object!
        obj = new(ptr)
        __incrrefcount(obj)
        finalizer(obj, __decrrefcount)
        return obj
    end
end

immutable List    end # Used in the signature of a Tcl list object.
immutable Command end # Used in the signature of a Tcl command object.

typealias TclObjList    TclObj{List}
typealias TclObjCommand TclObj{Command}

Base.string(obj::TclObj) =
    unsafe_string(ccall((:Tcl_GetString, libtcl), Cstring,
                        (TclObjPtr,), obj.ptr))

Base.show{T<:TclObj}(io::IO, ::MIME"text/plain", obj::T) =
    print(io, "$T($(string(obj)))")

Base.show{T<:TclObj{String}}(io::IO, ::MIME"text/plain", obj::T) =
    print(io, "$T(\"$(string(obj))\")")

# Provide short version for string interpolation in scripts (FIXME: also do
# that for other kind of objects).
Base.show{T<:Real}(io::IO, obj::TclObj{T}) =
    print(io, string(obj))

Base.show{T<:TclObj{List}}(io::IO, lst::T) =
    print(io, llength(lst), "-element(s) $T(\"$(string(lst))\")")

#------------------------------------------------------------------------------
# Tk widgets and other Tk objects.

abstract TkObject
abstract TkWidget     <: TkObject
abstract TkRootWidget <: TkWidget

# An image is parameterized by the image type (capitalized).
type TkImage{T} <: TkObject
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

abstract TkColor

immutable TkGray{T} <: TkColor
    gray::T
end

immutable TkRGB{T} <: TkColor
    r::T; g::T; b::T
end

immutable TkBGR{T} <: TkColor
    b::T; g::T; r::T
end

immutable TkRGBA{T} <: TkColor
    r::T; g::T; b::T; a::T
end

immutable TkBGRA{T} <: TkColor
    b::T; g::T; r::T; a::T
end

immutable TkARGB{T} <: TkColor
    a::T; r::T; g::T; b::T
end

immutable TkABGR{T} <: TkColor
    a::T; b::T; g::T; r::T
end


 gray{T}(c::TkGray{T}) :: T = c.gray
  red{T}(c::Union{TkRGB{T},TkBGR{T},TkRGBA{T},TkBGRA{T},TkARGB{T},TkABGR{T}}) :: T = c.r
green{T}(c::Union{TkRGB{T},TkBGR{T},TkRGBA{T},TkBGRA{T},TkARGB{T},TkABGR{T}}) :: T = c.g
 blue{T}(c::Union{TkRGB{T},TkBGR{T},TkRGBA{T},TkBGRA{T},TkARGB{T},TkABGR{T}}) :: T = c.b
alpha{T}(c::Union{TkRGBA{T},TkBGRA{T},TkARGB{T},TkABGR{T}}) :: T = c.a

Base.show{T<:TkGray}(io::IO, ::MIME"text/plain", c::T) =
    print(io, "$T(gray: $(string(gray(c))))")

Base.show{T<:Union{TkRGB,TkBGR}}(io::IO, ::MIME"text/plain", c::T) =
    print(io, "$T(red: $(string(red(c))), $(string(green(c))), $(string(blue(c))))")

Base.show{T<:Union{TkRGBA,TkABGR}}(io::IO, ::MIME"text/plain", c::T) =
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
