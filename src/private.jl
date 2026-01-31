# Private methods for the Julia interface to Tcl/Tk.

"""
    Tcl.isnull(ptr) -> bool

Return whether pointer `ptr` is null.

# See also

[`Tcl.null`](@ref).

"""
isnull(ptr::Union{Ptr,Cstring}) = ptr === null(ptr)

"""
    Tcl.null(ptr) -> nullptr
    Tcl.null(typeof(ptr)) -> nullptr

Return a null-pointer of the same type as `ptr`.

# See also

[`Tcl.isnull`](@ref).

"""
null(ptr::Union{Ptr,Cstring}) = null(typeof(ptr))
null(::Type{Ptr{T}}) where {T} = Ptr{T}(0)
null(::Type{Cstring}) = Cstring(C_NULL)

"""
    Tcl.value_type(x)
    Tcl.value_type(typeof(x))

Return the suitable type for storing a Julia object `x` in a Tcl object.

# See also

[`Tcl.new_object`](@ref) and [`Tcl.new_list`](@ref).

"""
value_type(x) = value_type(typeof(x))

"""
    Tcl.new_object(x) -> ptr

Return a pointer to a new Tcl object storing value `x`. The new object has a reference count
of `0`.

# See also

[`TclObj`](@ref), [`Tcl.new_list`](@ref), [`Tcl.value_type`](@ref),
[`Tcl.unsafe_get_refcnt`](@ref), [`Tcl.unsafe_incr_refcnt`](@ref), and
[`Tcl.unsafe_decr_refcnt`](@ref).

"""
new_object

"""
    Tcl.unsafe_get(T, objptr) -> val
    Tcl.unsafe_get(T, interp, objptr) -> val

Get a value of type `T` from Tcl object pointer `objptr`. Optional argument `interp` is a
pointer to a Tcl interpreter which, if non-null, may be used for error messages.

The reference count of `objptr` is left unchanged. Caller shall increment before and
decrement after the reference count of `objptr` to have it automatically preserved and/or
deleted.

!!! warning
    Unsafe function: object pointer must not be null and must remain valid during the call
    to this function, if non-null, `interp` must also remain valid during the call to this
    function.

"""
unsafe_get(::Type{TclObj}, objptr::ObjPtr) = _TclObj(objptr)
unsafe_get(::Type{T}, objptr::ObjPtr) where {T} = unsafe_get(T, null(InterpPtr), objptr)
unsafe_get(::Type{String}, interp::InterpPtr, objptr::ObjPtr) = unsafe_get(String, objptr)

"""
    Tcl.unsafe_get(T, interp) -> val

Get the result from Tcl interpreter pointer `interp` as a value of type `T`.

!!! warning
    Unsafe function: interpreter pointer must not be null and must remain valid during the
    call to this function.

"""
function unsafe_get(::Type{String}, interp::InterpPtr)
    return unsafe_string(Glue.Tcl_GetStringResult(interp))
end
function unsafe_get(::Type{T}, interp::InterpPtr) where {T}
    obj = Glue.Tcl_GetObjResult(interp)
    return unsafe_get(T, interp, obj)
end

# NOTE `value_type`, `new_object`, and `unsafe_get` must be consistent.
#
# Strings.
#
#     Julia strings and symbols are assumed to be Tcl strings. Julia characters are assumed
#     to Tcl strings of length 1.
#
#     There are two alternatives to create Tcl string objects: `Tcl_NewStringObj` or
#     `Tcl_NewUnicodeObj`. After some testings, the following works correctly. To build a
#     Tcl object from a Julia string, use `Ptr{UInt8}` instead of `Cstring` and provide the
#     number of bytes with `ncodeunit(str)`.
#
value_type(::Type{<:AbstractString}) = String
new_object(str::AbstractString) = new_object(String(str))
function new_object(str::Union{String,SubString{String}})
    GC.@preserve str begin
        return Glue.Tcl_NewStringObj(pointer(str), ncodeunits(str))
    end
end
function unsafe_get(::Type{String}, obj::ObjPtr)
    # NOTE `unsafe_string` catches that `ptr` must not be null so we do not check that.
    len = Ref{Cint}()
    return unsafe_string(Glue.Tcl_GetStringFromObj(obj, len), len[])
end
#
# Symbols are considered as Tcl strings.
#
value_type(::Type{Symbol}) = String
function new_object(sym::Symbol)
    GC.@preserve sym begin
        return Glue.Tcl_NewStringObj(sym, -1)
    end
end
#
# Characters are equivalent to Tcl strings of unit length.
#
value_type(::Type{<:AbstractChar}) = String
new_object(str::AbstractChar) = new_object(string(char))
function unsafe_get(::Type{T}, obj::ObjPtr) where {T<:AbstractChar}
    # FIXME Optimize this.
    str = unsafe_get(String, obj)
    length(str) == 1 || throw(Tcl.error("cannot convert Tcl object to `$T` value"))
    return first(str)
end
#
# Booleans.
#
#     Despite that it is possible to create boolean objects with `Tcl_NewBooleanObj`, Tcl
#     stores Booleans as `Cint`s and Booleans are retrieved as `Cint` objects.
#
value_type(::Type{Bool}) = Bool
new_object(val::Bool) = Glue.Tcl_NewBooleanObj(val)
function unsafe_get(::Type{Bool}, interp::InterpPtr, obj::ObjPtr)
    val = Ref{Cint}()
    status = Glue.Tcl_GetBooleanFromObj(interp, obj, val)
    status == TCL_OK || unsafe_error(interp, "cannot convert Tcl object to `Bool` value")
    return !iszero(val[])
end
#
# Integers.
#
#     For each integer type, we choose the Tcl integer which is large enough to store a
#     value of that type. Small unsigned integers may be problematic, but not so much as the
#     smallest Tcl integer type is `Cint` which is at least 32 bits.
#
# `Clong` type.
#
value_type(::Type{Clong}) = Clong
new_object(val::Clong) = Glue.Tcl_NewLongObj(val)
function unsafe_get(::Type{Clong}, interp::InterpPtr, obj::ObjPtr)
    val = Ref{Clong}()
    status = Glue.Tcl_GetLongFromObj(interp, obj, val)
    status == TCL_OK || unsafe_error(interp, "cannot convert Tcl object to `$Clong` value")
    return val[]
end
#
# `Cint` if not the same thing as `Clong`.
#
if Cint != Clong
    value_type(::Type{Cint}) = Cint
    new_object(val::Cint) = Glue.Tcl_NewIntObj(val)
    function unsafe_get(::Type{Cint}, interp::InterpPtr, obj::ObjPtr)
        val = Ref{Cint}()
        status = Glue.Tcl_GetIntFromObj(interp, obj, val)
        status == TCL_OK || unsafe_error(interp, "cannot convert Tcl object to `$Cint` value")
        return val[]
    end
end
#
# `WideInt` if not the same thing as `Clong` or `Cint`.
#
if WideInt != Clong && WideInt != Cint
    value_type(::Type{WideInt}) = WideInt
    new_object(val::WideInt) = Glue.Tcl_NewWideIntObj(val)
    function unsafe_get(::Type{WideInt}, interp::InterpPtr, obj::ObjPtr)
        val = Ref{WideInt}()
        status = Glue.Tcl_GetWideIntFromObj(interp, obj, val)
        status == TCL_OK || unsafe_error(interp, "cannot convert Tcl object to `$WideInt` value")
        return val[]
    end
end
#
# Other integer types.
#
function value_type(::Type{T}) where {T<:Integer}
    if isbitstype(T)
        sizeof(T) ≤ sizeof(Cint) && return Cint
        sizeof(T) ≤ sizeof(Clong) && return Clong
    end
    return WideInt
end
function new_object(val::T) where {T<:Integer}
    S = value_type(T)
    T <: S && error("conversion must change object's type")
    return new_object(convert(S, val)::S)
end
function unsafe_get(::Type{T}, interp::InterpPtr, obj::ObjPtr) where {T<:Integer}
    S = value_type(T)
    T <: S && error("conversion must change object's type")
    return convert(T, unsafe_get(S, interp, obj))::T
end
#
# Floats.
#
#     Non-integer reals are considered as double precision floating-point numbers.
#
value_type(::Type{<:Real}) = Cdouble
new_object(val::Real) = Glue.Tcl_NewDoubleObj(val)
function unsafe_get(::Type{Cdouble}, interp::InterpPtr, obj::ObjPtr)
    val = Ref{Cdouble}()
    status = Glue.Tcl_GetDoubleFromObj(interp, obj, val)
    status == TCL_OK || unsafe_error(interp, "cannot convert Tcl object to `$Cdouble` value")
    return val[]
end
function unsafe_get(::Type{T}, interp::InterpPtr, obj::ObjPtr) where {T<:AbstractFloat}
    return convert(T, unsafe_get(Cdouble, interp, obj))::T
end
#
# Tuples are stored as Tcl lists.
#
function new_object(tup::Tuple)
    list = new_list()
    try
        for item in tup
            unsafe_append_element(interp, list, item)
        end
    catch
        unsafe_decr_refcnt(list)
        retrow()
    end
    return list
end
#
# Dense vector of bytes are stored as Tcl `bytearray` object.
#
value_type(::Type{T}) where {T<:DenseVector{UInt8}} = T
new_object(arr::DenseVector{UInt8}) = Glue.Tcl_NewByteArrayObj(arr, length(arr))
function unsafe_get(::Type{T}, interp::InterpPtr,
                    obj::ObjPtr) where {T<:Union{Vector{UInt8},Memory{UInt8}}}
    return unsafe_get(T, obj) # `interp` not needed
end
function unsafe_get(::Type{T}, obj::ObjPtr) where {T<:Union{Vector{UInt8},Memory{UInt8}}}
    len = Ref{Cint}()
    ptr = Glue.Tcl_GetByteArrayFromObj(obj, len)
    len = Int(len[])::Int
    arr = T(undef, len)
    len > 0 && Libc.memcpy(arr, ptr, len)
    return arr
end
#
# Error catchers for unsupported Julia types.
#
@noinline value_type(::Type{T}) where {T} =
    throw(TclError("unknown Tcl object type for Julia objects of type `$T`"))
@noinline new_object(val::T) where {T} =
    throw(TclError("cannot convert an instance of type `$T` into a Tcl object"))
@noinline unsafe_get(::Type{T}, interp::InterpPtr, obj::ObjPtr) where {T} =
    throw(TclError("retrieving an instance of type `$T` from a Tcl object is not unsupported"))

"""
    Tcl.unsafe_incr_refcnt(objptr) -> objptr

Increment the reference count of the Tcl object given its pointer and return it.

!!! warning
    Unsafe function: object pointer must not be null and must remain valid during the call
    to this function.

# See also

[`Tcl.unsafe_decr_refcnt`](@ref) and [`Tcl.unsafe_get_refcnt`](@ref).

"""
unsafe_incr_refcnt(obj::ObjPtr) = Glue.Tcl_IncrRefCount(obj)

"""
    Tcl.unsafe_decr_refcnt(objptr) -> refcnt

Decrement the reference count of the Tcl object given its pointer and return its new
reference count. If `refcnt < 1` holds, the Tcl object has been released and `objptr` shall
no longer be used.

!!! warning
    Unsafe function: object pointer must not be null and must remain valid during the call
    to this function.

# See also

[`Tcl.unsafe_incr_refcnt`](@ref) and [`Tcl.unsafe_get_refcnt`](@ref).

"""
unsafe_decr_refcnt(obj::ObjPtr) = Glue.Tcl_DecrRefCount(obj)

"""
    Tcl.unsafe_get_refcnt(objptr) -> refcnt

Return the current reference count of the Tcl object at address `objptr`.

!!! warning
    Unsafe function: object pointer must not be null and must remain valid during the call
    to this function.

# See also

[`Tcl.unsafe_incr_refcnt`](@ref) and [`Tcl.unsafe_decr_refcnt`](@ref).

"""
unsafe_get_refcnt(obj::ObjPtr) = Glue.Tcl_GetRefCount(obj)

function _getproperty(obj::TclObj, ::Val{:refcnt})
    GC.@preserve obj begin
        ptr = pointer(obj)
        return isnull(ptr) ? -one(Glue.Tcl_Obj_refCount_type) : unsafe_get_refcnt(ptr)
    end
end

"""
    Tcl.unsafe_get_typename(ptr) -> sym::Symbol

Return the symbolic type name of Tcl object pointer `ptr`. The result can be:

- `:null` for a null Tcl object pointer.

- `:string` for an unspecific object type (i.e., null type pointer null).

- `:int`, `:double`, `:bytearray`, `:list`, `:bytecode`, etc. for an object
  with a specific

!!! warning
    The function is *unsafe* as `ptr` may be null and otherwise must be valid for the
    duration of the call (i.e., protected form being garbage collected).

""" unsafe_get_typename

function _getproperty(obj::TclObj, ::Val{:type})
    GC.@preserve obj begin
        return unsafe_get_typename(pointer(obj))
    end
end

# The table of known types is updated while objects of new types are created because seeking
# for an existing type is much faster than creating the mutable `TclObj` structure so the
# overhead is negligible.
const _known_types = Tuple{ObjTypePtr,Symbol}[]

function unsafe_get_typename(objPtr::ObjPtr)
    isnull(objPtr) && return :null # null object pointer
    typePtr = unsafe_load(Ptr{Glue.Tcl_Obj_typePtr_type}(objPtr + Glue.Tcl_Obj_typePtr_offset))
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
        namePtr = unsafe_load(Ptr{Glue.Tcl_ObjType_name_type}(typePtr + Glue.Tcl_ObjType_name_offset))
        isnull(namePtr) && unexpected_null("Tcl object type name")
        sym = Symbol(unsafe_string(namePtr))
    end
    push!(_known_types, (typePtr, sym))
    return sym
end

#---------------------------------------------------------------------------------- Errors -

Base.showerror(io::IO, ex::TclError) = print(io, "Tcl/Tk error: ", ex.msg)

@noinline argument_error(mesg::AbstractString) = throw(ArgumentError(mesg))
@noinline argument_error(arg, args...) = throw(ArgumentError(string(arg, args...)))

@noinline assertion_error(mesg::AbstractString) = throw(AssertionError(mesg))
@noinline assertion_error(arg, args...) = throw(AssertionError(string(arg, args...)))

@noinline unexpected_null(str::AbstractString) = assertion_error("unexpected NULL ", str)

"""
    Tcl.unsafe_error(interp, mesg)

Throw a Tcl error. If `interp` is a non-null pointer to a Tcl interpreter, the error message
is taken from interpreter's result; otherwise, the error message is `mesg`.

!!! warning
    Unsafe function: if non-null, interpreter pointer must remain valid during the call to
    this function.

# See also

[`Tcl.unsafe_get`](@ref).

"""
@noinline function unsafe_error(interp::InterpPtr, mesg::AbstractString)
    throw(TclError(unsafe_error_message(interp, mesg)))
end

function unsafe_error_message(interp::InterpPtr, mesg::AbstractString)
    if !isnull(interp)
        cstr = Glue.Tcl_GetStringResult(interp)
        if !isnull(cstr) && !iszero(unsafe_load(Ptr{UInt8}(cstr)))
            return unsafe_string(cstr)
        end
    end
    return String(mesg)
end
