"""
    TclObj(val) -> obj

Return a Tcl object storing value `val`. If `val` is a Tcl object, it is returned unchanged.
Call `copy(obj)` to have an independent copy.

Call `convert(T, obj)` to get a value of type `T` from Tcl object `obj`.

# Object type

Tcl objects have a type given by `obj.type` and reflecting their current internal state. For
efficiency, this type may change depending on how the object is used and provided this does
not modify the content of the object.

The content of a Tcl object may always be converted into a string. `string(obj)` or
`String(obj)` return a copy of this string.

If the content of a Tcl object is valid as a list, the object may be indexed, elements may
be added, deleted, etc.

# Properties

Tcl objects have the following properties:

- `obj.refcnt` the reference count of `obj`. If `obj.refcnt > 1`, the object is shared and
  must be copied before being modified.

- `obj.ptr` the pointer to the Tcl object, this is the same as `pointer(obj)`.

- `obj.type` the symbolic current type of `obj`. Common types are:

  - `:null` for a null Tcl object pointer.

  - `:string` for an undefined Tcl object type.

  - `:int` for integers.

  - `:double` for floating-point.

  - `:bytearray` for an array of raw bytes.

  - `:list` for a list of objects.

  - `:bytecode` for compiled byte code.


# See also

[`Tcl.list`](@ref) or [`Tcl.concat`](@ref) for building Tcl objects to efficiently store
arguments of Tcl commands.

Private methods [`Tcl.value_type`](@ref) and [`Tcl.new_object`](@ref) may be extended to
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
    if isnull(objptr) || unsafe_get_refcnt(objptr) < 𝟙
        return objptr
    else
        return Glue.Tcl_DuplicateObj(objptr)
    end
end

Base.repr(obj::TclObj) = String(obj) # FIXME
Base.string(obj::TclObj) = String(obj)
Base.String(obj::TclObj) = convert(String, obj)

Base.convert(::Type{TclObj}, obj::TclObj) = obj
function Base.convert(::Type{T}, obj::TclObj) where {T}
    GC.@preserve obj begin
        val = unsafe_get(value_type(T), checked_pointer(obj))
        return convert(T, val)::T
    end
end

# FIXME unused
@noinline function throw_conversion_error(::Type{T}, obj::TclObj) where {T}
    io = IOBuffer()
    print(io, "cannot convert \"")
    summary(io, obj)
    print(io, "\" to type `", T, "`")
    throw(ErrorException(String(take!(io))))
end

# Extend base methods for objects.
function Base.summary(io::IO, obj::TclObj)
    print(io, "TclObj(")
    type = obj.type
    if type == :int
        print(io, convert(WideInt, obj))
    elseif type == :double
        print(io, convert(Cdouble, obj))
    elseif type == :bytearray
        print(io, "UInt8[...]")
    elseif type == :list
        print(io, "...")
    elseif type != :null
        print(io, repr(string(obj)))
    end
    print(io, ")")
end

function Base.summary(obj::TclObj)
    io = IOBuffer()
    summary(io, obj)
    return String(take!(io))
end

Base.show(io::IO, ::MIME"text/plain", obj::TclObj) = summary(io, obj)
Base.show(io::IO, obj::TclObj) = summary(io, obj)

# It is forbidden to access to the fields of a `TclObj` by the `obj.key` syntax.
Base.propertynames(obj::TclObj) = (:ptr, :refcnt, :type)
Base.getproperty(obj::TclObj, key::Symbol) = _getproperty(obj, Val(key))
Base.setproperty!(obj::TclObj, key::Symbol, val) = _setproperty!(obj, Val(key), val)

_getproperty(obj::TclObj, ::Val{key}) where {key} = throw(KeyError(key))
_setproperty!(obj::TclObj, key::Symbol, val) = throw(KeyError(key))

"""
    Tcl.iswritable(obj) -> bool

Return whether Tcl object `obj` is writable, that is whether its pointer is non-null and it
has at most one reference.

"""
Base.isreadable(obj::ManagedObject) = isreadable(pointer(obj))
Base.isreadable(objptr::ObjPtr) = !isnull(objptr)

function assert_readable(objptr::ObjPtr)
    isnull(objptr) && assertion_error("null Tcl object has no value")
    return objptr
end

"""
    Tcl.iswritable(obj) -> bool

Return whether Tcl object `obj` is writable, that is whether its pointer is non-null and it
has at most one reference.

"""
Base.iswritable(obj::ManagedObject) = iswritable(pointer(obj))
Base.iswritable(objptr::ObjPtr) = !isnull(objptr) && unsafe_get_refcnt(objptr) ≤ 𝟙

function assert_writable(objptr::ObjPtr)
    isnull(objptr) && assertion_error("null Tcl object is not writable")
    unsafe_get_refcnt(objptr) > 𝟙 && assertion_error("shared Tcl object is not writable")
    return objptr
end

Base.unsafe_convert(::Type{ObjPtr}, obj::TclObj) = checked_pointer(obj)
Base.pointer(obj::TclObj) = getfield(obj, :ptr)

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
        isnull(newptr) || unsafe_incr_refcnt(newptr)
        isnull(oldptr) || unsafe_decr_refcnt(oldptr)
        setfield!(obj, :ptr, newptr)
    end
    nothing
end
