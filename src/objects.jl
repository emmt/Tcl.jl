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
    if isnull(objptr) || unsafe_get_refcnt(objptr) < 𝟙
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
Base.iswritable(objptr::ObjPtr) = !isnull(objptr) && unsafe_get_refcnt(objptr) ≤ 𝟙

function assert_writable(objptr::ObjPtr)
    isnull(objptr) && assertion_error("null Tcl object is not writable")
    unsafe_get_refcnt(objptr) > 𝟙 && assertion_error("shared Tcl object is not writable")
    return objptr
end

# The string representation of a Tcl object is owned by Tcl's value manager, so getting a C
# string pointer to this string is always safe unless object pointer is null.
Base.unsafe_convert(::Type{Cstring}, obj::TclObj) = Tcl_GetString(checked_pointer(obj))
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
