"""
    TclObj(val) -> obj

Return a Tcl object storing value `val`. The initial type of the Tcl object, given by
`obj.type`, depends on the type of `val`:

- A string, symbol, or character is stored as a Tcl `:string`.

- A Boolean or integer is stored as a Tcl `:int`.

- A non-integer real is stored as a Tcl `:double`.

- A dense vector of bytes (`UInt8`) is stored as a Tcl `:bytearray`.

- A tuple is stored as a Tcl `:list`.

- A Tcl object is returned unchanged. Call `copy` to have an independent copy.

Beware that `obj.type` reflects the *current internal state* of `obj`. Indeed, for
efficiency, this type may change depending on how the object is used. For example, after
having evaluated a script in a Tcl string object, the object internal state becomes
`:bytecode` to reflect that it now stores compiled byte code.

Call `convert(T, obj)` to get a value of type `T` from Tcl object `obj`. The content of a
Tcl object may always be converted into a string. Methods `convert(String, obj)`,
`string(obj)`, and `String(obj)` yield a copy of this string.

If the content of a Tcl object is valid as a list, the object may be indexed, elements may
be added, deleted, etc.

# Properties

Tcl objects have the following properties:

- `obj.refcnt` yields the reference count of `obj`. If `obj.refcnt > 1`, the object is
  shared and must be copied before being modified.

- `obj.ptr` yields the pointer to the Tcl object, this is the same as `pointer(obj)`.

- `obj.type` yields the symbolic current type of `obj`.

# See also

[`Tcl.list`](@ref) or [`Tcl.concat`](@ref) for building Tcl objects to efficiently store
arguments of Tcl commands.

Private methods [`Tcl.Private.value_type`](@ref) and [`Tcl.Private.new_object`](@ref) may be extended to
convert other types of value to Tcl object.

"""
TclObj(obj::TclObj) = obj
TclObj() = _TclObj(null(ObjPtr))
TclObj(val) = _TclObj(new_object(val))

function Base.copy(obj::TclObj)
    local objptr
    GC.@preserve obj begin
        objptr = unsafe_duplicate(pointer(obj))
    end
    return _TclObj(objptr)
end

function unsafe_duplicate(objptr::ObjPtr)
    if isnull(objptr) || Tcl_GetRefCount(objptr) < 𝟙
        return objptr
    else
        return Tcl_DuplicateObj(objptr)
    end
end

Base.string(obj::TclObj) = String(obj)
Base.String(obj::TclObj) = convert(String, obj)

Base.convert(::Type{TclObj}, obj::TclObj) = obj
function Base.convert(::Type{T}, obj::TclObj) where {T}
    GC.@preserve obj begin
        val = unsafe_get(value_type(T), checked_pointer(obj))
        return convert(T, val)::T
    end
end

Base.:(==)(A::TclObj, B::TclObj) = isequal(A, B)
Base.:(==)(A::TclObj, B::Union{AbstractString,Symbol}) = isequal(A, B)
Base.:(==)(A::Union{AbstractString,Symbol}, B::TclObj) = isequal(A, B)

function Base.isequal(A::TclObj, B::TclObj)
    # TODO Optimize depending on internal representation?
    GC.@preserve A B begin
        A_ptr = pointer(A)
        B_ptr = pointer(B)
        (A_ptr == B_ptr) && return true
        (isnull(A_ptr) || isnull(B_ptr)) && return false
        A_len = Ref{Cint}()
        A_buf = Tcl_GetStringFromObj(A_ptr, A_len)
        B_len = Ref{Cint}()
        B_buf = Tcl_GetStringFromObj(B_ptr, B_len)
        (A_len[] == B_len[]) || return false
        return iszero(unsafe_memcmp(A_buf, B_buf, B_len[]))
    end
end

Base.isequal(A::Union{AbstractString,Symbol}, B::TclObj) = isequal(B, A)

Base.isequal(A::TclObj, B::AbstractString) = isequal(A, String(B)::String)

function Base.isequal(A::TclObj, B::FastString)
    GC.@preserve A B begin
        A_ptr = pointer(A)
        isnull(A_ptr) && return false
        A_len = Ref{Cint}()
        A_buf = Tcl_GetStringFromObj(A_ptr, A_len)
        B_len = sizeof(B) # number of bytes in B
        (A_len[] == B_len) || return false
        return iszero(unsafe_memcmp(A_buf, B, B_len))
    end
end

# TODO check print(io, obj)
function Base.write(io::IO, obj::TclObj)
    return GC.@preserve obj unsafe_write(io, pointer(obj))
end

function Base.unsafe_write(io::IO, objptr::ObjPtr)
    isnull(objptr) && return 0
    len = Ref{Cint}()
    buf = Tcl_GetStringFromObj(objptr, len)
    return Int(unsafe_write(io, buf, len[]))::Int
end

# Extend base methods for objects.
function Base.summary(io::IO, obj::TclObj)
    print(io, "TclObj: ")
    show_value(io, obj)
end
function Base.summary(obj::TclObj)
    io = IOBuffer()
    summary(io, obj)
    return String(take!(io))
end

function Base.repr(obj::TclObj)
    io = IOBuffer()
    show(io, obj)
    return String(take!(io))
end

Base.show(io::IO, ::MIME"text/plain", obj::TclObj) = show(io, obj)
function Base.show(io::IO, obj::TclObj)
    print(io, "TclObj(")
    show_value(io, obj)
    print(io, ")")
end

function show_value(io::IO, obj::TclObj)
    type = obj.type
    if type == :int
        print(io, convert(WideInt, obj))
    elseif type == :double
        print(io, convert(Cdouble, obj))
    elseif type == :bytearray
        print(io, "UInt8[")
        GC.@preserve obj begin
            len = Ref{Cint}()
            ptr = Tcl_GetByteArrayFromObj(obj, len)
            len = Int(len[])::Int
            if len ≤ 10
                for i in 1:len
                    i > 1 && print(io, ", ")
                    show(io, unsafe_load(ptr, i))
                end
            else
                for i in 1:5
                    i > 1 && print(io, ", ")
                    show(io, unsafe_load(ptr, i))
                end
                print(io, ", ...")
                for i in len-4:len
                    print(io, ", ")
                    show(io, unsafe_load(ptr, i))
                end
            end
        end
        print(io, "]")
    elseif type == :list
        print(io, "(")
        len = length(obj)
        if len ≤ 10
            for i in 1:len
                i > 1 && print(io, ", ")
                show_value(io, obj[i])
            end
        else
            for i in 1:5
                i > 1 && print(io, ", ")
                show_value(io, obj[i])
            end
            print(io, ", ...")
            for i in len-4:len
                print(io, ", ")
                show_value(io, obj[i])
            end
        end
        print(io, ",)")
    elseif type == :null
        print(io, "#= NULL =#")
    else
        show(io, string(obj))
    end
end

# It is forbidden to access to the fields of a `TclObj` by the `obj.key` syntax.
Base.propertynames(obj::TclObj) = (:ptr, :refcnt, :type)
Base.getproperty(obj::TclObj, key::Symbol) = _getproperty(obj, Val(key))
Base.setproperty!(obj::TclObj, key::Symbol, val) = _setproperty!(obj, Val(key), val)

_getproperty(obj::TclObj, ::Val{key}) where {key} = throw(KeyError(key))
_setproperty!(obj::TclObj, key::Symbol, val) = throw(KeyError(key))

function _getproperty(obj::TclObj, ::Val{:refcnt})
    GC.@preserve obj begin
        ptr = pointer(obj)
        return isnull(ptr) ? -one(Tcl_Obj_refCount_type) : Tcl_GetRefCount(ptr)
    end
end

function _getproperty(obj::TclObj, ::Val{:type})
    GC.@preserve obj begin
        return unsafe_get_typename(pointer(obj))
    end
end

"""
    iswritable(obj) -> bool

Return whether Tcl object `obj` is writable, that is whether its pointer is non-null and it
has at most one reference.

"""
Base.isreadable(obj::TclObj) = isreadable(pointer(obj))
Base.isreadable(objptr::ObjPtr) = !isnull(objptr)

function assert_readable(objptr::ObjPtr)
    isnull(objptr) && assertion_error("null Tcl object has no value")
    return objptr
end

"""
    iswritable(obj) -> bool

Return whether Tcl object `obj` is writable, that is whether its pointer is non-null and it
has at most one reference.

"""
Base.iswritable(obj::TclObj) = iswritable(pointer(obj))
Base.iswritable(objptr::ObjPtr) = !isnull(objptr) && Tcl_GetRefCount(objptr) ≤ 𝟙

function assert_writable(objptr::ObjPtr)
    isnull(objptr) && assertion_error("null Tcl object is not writable")
    Tcl_GetRefCount(objptr) > 𝟙 && assertion_error("shared Tcl object is not writable")
    return objptr
end

function finalize(obj::TclObj)
    obj.ptr = null(ObjPtr)
    return nothing
end

function _getproperty(obj::TclObj, ::Val{:ptr})
    return getfield(obj, :ptr)
end

function _setproperty!(obj::TclObj, ::Val{:ptr}, newptr::ObjPtr)
    oldptr = getfield(obj, :ptr)
    if newptr != oldptr
        isnull(newptr) || Tcl_IncrRefCount(newptr)
        isnull(oldptr) || Tcl_DecrRefCount(oldptr)
        setfield!(obj, :ptr, newptr)
    end
    nothing
end

"""
    Tcl.Private.get_objptr(obj::ManagedObject) -> objptr

Return a pointer to the Tcl object associated with `obj`. The returned object is at least
referenced by its parent `obj` which shall be preserved form being garbage collected while
`objptr` is used.

# See also

[`TclObj`](@ref), [`Tcl.Private.ManagedObject`](@ref), and [`Tcl.Private.new_object`](@ref),

"""
get_objptr(obj::TclObj) = pointer(obj)

"""
    Tcl.Private.value_type(x)
    Tcl.Private.value_type(typeof(x))

Return the suitable type for storing a Julia object `x` in a Tcl object.

# See also

[`Tcl.Private.new_object`](@ref) and [`Tcl.Private.new_list`](@ref).

"""
value_type(x) = value_type(typeof(x))

"""
    Tcl.Private.new_object(x) -> ptr

Return a pointer to a new Tcl object storing value `x`. The new object has a reference count
of `0`.

# See also

[`TclObj`](@ref), [`Tcl.Private.new_list`](@ref), [`Tcl.Private.value_type`](@ref),
[`Tcl.Private.Tcl_GetRefCount`](@ref), [`Tcl.Private.Tcl_IncrRefCount`](@ref), and
[`Tcl.Private.Tcl_DecrRefCount`](@ref).

"""
new_object

"""
    Tcl.Private.unsafe_get(T, objptr) -> val
    Tcl.Private.unsafe_get(T, interp, objptr) -> val

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
    Tcl.Private.unsafe_get(T, interp) -> val

Get the result from Tcl interpreter pointer `interp` as a value of type `T`.

!!! warning
    Unsafe function: interpreter pointer must not be null and must remain valid during the
    call to this function.

"""
function unsafe_get(::Type{String}, interp::InterpPtr)
    return unsafe_string(Tcl_GetStringResult(interp))
end
function unsafe_get(::Type{T}, interp::InterpPtr) where {T}
    obj = Tcl_GetObjResult(interp)
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
        return Tcl_NewStringObj(pointer(str), ncodeunits(str))
    end
end
function unsafe_get(::Type{String}, obj::ObjPtr)
    # NOTE `unsafe_string` catches that `ptr` must not be null so we do not check that.
    len = Ref{Cint}()
    return unsafe_string(Tcl_GetStringFromObj(obj, len), len[])
end
#
# Symbols are considered as Tcl strings.
#
value_type(::Type{Symbol}) = String
function new_object(sym::Symbol)
    GC.@preserve sym begin
        return Tcl_NewStringObj(sym, -1)
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
    length(str) == 1 || throw(TclError("cannot convert Tcl object to `$T` value"))
    return first(str)
end
#
# Booleans.
#
#     Despite that it is possible to create boolean objects with `Tcl_NewBooleanObj`, Tcl
#     stores Booleans as `Cint`s and Booleans are retrieved as `Cint` objects.
#
value_type(::Type{Bool}) = Bool
new_object(val::Bool) = Tcl_NewBooleanObj(val)
function unsafe_get(::Type{Bool}, interp::InterpPtr, obj::ObjPtr)
    val = Ref{Cint}()
    status = Tcl_GetBooleanFromObj(interp, obj, val)
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
new_object(val::Clong) = Tcl_NewLongObj(val)
function unsafe_get(::Type{Clong}, interp::InterpPtr, obj::ObjPtr)
    val = Ref{Clong}()
    status = Tcl_GetLongFromObj(interp, obj, val)
    status == TCL_OK || unsafe_error(interp, "cannot convert Tcl object to `$Clong` value")
    return val[]
end
#
# `Cint` if not the same thing as `Clong`.
#
if Cint != Clong
    value_type(::Type{Cint}) = Cint
    new_object(val::Cint) = Tcl_NewIntObj(val)
    function unsafe_get(::Type{Cint}, interp::InterpPtr, obj::ObjPtr)
        val = Ref{Cint}()
        status = Tcl_GetIntFromObj(interp, obj, val)
        status == TCL_OK || unsafe_error(interp, "cannot convert Tcl object to `$Cint` value")
        return val[]
    end
end
#
# `WideInt` if not the same thing as `Clong` or `Cint`.
#
if WideInt != Clong && WideInt != Cint
    value_type(::Type{WideInt}) = WideInt
    new_object(val::WideInt) = Tcl_NewWideIntObj(val)
    function unsafe_get(::Type{WideInt}, interp::InterpPtr, obj::ObjPtr)
        val = Ref{WideInt}()
        status = Tcl_GetWideIntFromObj(interp, obj, val)
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
new_object(val::Real) = Tcl_NewDoubleObj(val)
function unsafe_get(::Type{Cdouble}, interp::InterpPtr, obj::ObjPtr)
    val = Ref{Cdouble}()
    status = Tcl_GetDoubleFromObj(interp, obj, val)
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
            unsafe_append_element(list, item)
        end
    catch
        Tcl_DecrRefCount(list)
        rethrow()
    end
    return list
end
#
# Dense vector of bytes are stored as Tcl `bytearray` object.
#
value_type(::Type{T}) where {T<:DenseVector{UInt8}} = T
new_object(arr::DenseVector{UInt8}) = Tcl_NewByteArrayObj(arr, length(arr))
function unsafe_get(::Type{T}, interp::InterpPtr,
                    obj::ObjPtr) where {T<:Union{Vector{UInt8},Memory{UInt8}}}
    return unsafe_get(T, obj) # `interp` not needed
end
function unsafe_get(::Type{T}, obj::ObjPtr) where {T<:Union{Vector{UInt8},Memory{UInt8}}}
    len = Ref{Cint}()
    ptr = Tcl_GetByteArrayFromObj(obj, len)
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
