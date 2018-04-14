#
# objects.jl -
#
# Management of Tcl objects.
#


# Extend base methods for objects.

# FIXME: A slight optimization is possible here because we know that
#        the object pointer cannot be NULL.
Base.string(obj::TclObj) = __objptr_to_string(obj.ptr)

Base.show(io::IO, ::MIME"text/plain", obj::T) where {T<:TclObj} =
    print(io, "$T($(string(obj)))")

Base.show(io::IO, ::MIME"text/plain", obj::T) where {T<:TclObj{String}} =
    print(io, "$T(\"$(string(obj))\")")

# Provide short version for string interpolation in scripts (FIXME: also do
# that for other kind of objects).
Base.show(io::IO, obj::TclObj{<:Real}) =
    print(io, string(obj))

Base.show(io::IO, lst::T) where {T<:TclObj{List}} =
    print(io, llength(lst), "-element(s) $T(\"$(string(lst))\")")


"""
```julia
Tcl.getvalue(obj)
````

yields the value of a Tcl object.  The type of the result corresponds to
the internal representation of the object.

"""
getvalue(obj::TclObj{String}) = __objptr_to_string(obj.ptr)
getvalue(obj::TclObj{T}) where {T<:Union{Bool,Cint,Clong,Int64,Cdouble,List}} =
    __objptr_to_value(T, obj.ptr)


"""
```julia
TclObj(value)
```

yields a new instance of `TclObj` which stores a Tcl object pointer.  This
method may be overloaded to implement means to pass other kinds of arguments to
Tcl.  Tcl objects are used to efficiently build Tcl commands in the form of
`TclObj{List}`.

"""
TclObj(obj::TclObj) = obj


"""
```julia
__newobj(value)
```

yields a pointer to a temporary Tcl object with given value.  This method may
thrown an exception.

""" __newobj


# Booleans.
#
#     Tcl boolean is in fact stored as an `Cint` despite the fact that it is
#     possible to create boolean objects, they are retrieved as `Cint` objects.

TclObj(value::Bool) = TclObj{Bool}(__newobj(value))

function __newobj(value::Bool)
    objptr = ccall((:Tcl_NewBooleanObj, libtcl), TclObjPtr,
                   (Cint,), (value ? one(Cint) : zero(Cint)))
    if objptr == C_NULL
        tclerror("failed to create a Tcl boolean object")
    end
    return objptr
end


# Integers.
#
#     For each integer type, we choose the Tcl integer which is large enough to
#     store a value of that type.  Small unsigned integers may be problematic,
#     but not so much as the smallest Tcl integer type is `Cint` which is at
#     least 32 bits.

for Tj in (Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64)
    (Tc, f) = (sizeof(Tj) ≤ sizeof(Cint) ? (Cint, :Tcl_NewIntObj) :
               sizeof(Tj) ≤ sizeof(Clong) ? (Clong, :Tcl_NewLongObj) :
               (Clonglong, :Tcl_NewWideIntObj))
    tup = (f, libtcl)
    @eval begin

        TclObj(value::$Tj) = TclObj{$Tc}(__newobj(value))

        function __newobj(value::$Tj)
            objptr = ccall($tup, TclObjPtr, ($Tc,), value)
            if objptr == C_NULL
                tclerror("failed to create a Tcl integer object")
            end
            return objptr
        end

    end

end


# Floats.
#
#     All floating point types, rationals and irrationals yield `Cdouble` Tcl
#     objects.

TclObj(value::Union{Irrational,Rational,AbstractFloat}) =
    TclObj{Cdouble}(__newobj(value))

__newobj(value::Union{Irrational,Rational,AbstractFloat}) =
    __newobj(convert(Cdouble, value))

function __newobj(value::Cdouble)
    objptr = ccall((:Tcl_NewDoubleObj, libtcl), TclObjPtr,
                   (Cdouble,), value)
    if objptr == C_NULL
        tclerror("failed to create a Tcl floating-point object")
    end
    return objptr
end


# Strings.
#
#     Julia strings and symbols are assumed to be Tcl strings.  Julia
#     characters are assumed to Tcl strings of length 1.
#
#     There are two alternatives to create Tcl string objects:
#     `Tcl_NewStringObj` or `Tcl_NewUnicodeObj`.  After some testings (see my
#     notes), the following works correctly.  To build a Tcl object from a
#     Julia string, use `Ptr{UInt8}` instead of `Cstring` and provide the
#     number of bytes with `sizeof(str)`.


TclObj(value::StringOrSymbol) = TclObj{String}(__newobj(value))
TclObj(c::Char) = TclObj{String}(__newobj(c))

__newobj(sym::Symbol) = __newobj(string(sym))
__newobj(c::Char) = __newobj(string(c))

function __newobj(str::AbstractString, nbytes::Integer = sizeof(str))
    objptr = ccall((:Tcl_NewStringObj, libtcl), TclObjPtr,
                   (Ptr{Cchar}, Cint), str, nbytes)
    if objptr == C_NULL
        tclerror("failed to create a Tcl string object")
    end
    return objptr
end

function __newstringobj(ptr::Ptr{T}, nbytes::Integer) where {T<:Byte}
    objptr = ccall((:Tcl_NewStringObj, libtcl), TclObjPtr,
                   (Ptr{T}, Cint), ptr, nbytes)
    if objptr == C_NULL
        tclerror("failed to create a Tcl string object")
    end
    return objptr
end

# Void and nothing.
#
#     Nothing is loosely aliased to "" in Tcl.  Could also be an empty list.

TclObj(::Void) = TclObj{Void}(__newobj(nothing))

__newobj(::Void) = __newobj("", 0)


# Functions.
#
#     Functions are used for callbacks.

TclObj(f::Function) = TclObj{Command}(__newobj(f))

__newobj(f::Function) =
    __newobj(createcommand(__currentinterpreter[], f))


# Unsupported objects.
#
#     These fallbacks are only meet for unsupported types.

TclObj(::T) where T = __unsupported_object_type(T)

__newobj(::T) where T = __unsupported_object_type(T)

__unsupported_object_type(::Type{T}) where T =
    tclerror("making a Tcl object for type $T is not supported")


# Arrays of bytes.
#
#     These come in 2 flavors: strings and byte array.

__newbytearrayobj(arr::DenseArray{T}) where {T<:Byte} =
    __newbytearrayobj(pointer(arr), size(arr))

function __newbytearrayobj(ptr::Ptr{T}, nbytes::Integer) where {T<:Byte}
    objptr = ccall((:Tcl_NewByteArrayObj, libtcl), TclObjPtr,
          (Ptr{T}, Cint), ptr, nbytes)
    if objptr == C_NULL
        tclerror("failed to create a Tcl byte array object")
    end
    return objptr
end


"""
```julia
__objptr(arg)
```

yields a pointer to a Tcl object corresponding to argument `arg`.  This may
create a new (temporary) object so caller should make sure the reference count
of the result is correctly managed.  An exception may be thrown if the argument
cannot be converted into a Tcl object.

"""
__objptr(obj::TclObj) = obj.ptr
__objptr(value) = __newobj(value)


#------------------------------------------------------------------------------

# Fake Julia structure which reflects the layout of a Tcl_Obj and is intended
# to compute the offset of the various fields of a Tcl object.
struct __TclObj
    # Object's Reference count.  When 0 the object will be freed.
    refCount::Cint

    # Object's string representation.  This points to the first byte of the
    # object's string representation.  The array must be followed by a null
    # byte (i.e., at offset `length`) but may also contain embedded null
    # characters.  The array's storage is allocated by `ckalloc`.  NULL means
    # the string representation is invalid and must be regenerated from the
    # internal representation.  Clients should use Tcl_GetStringFromObj or
    # Tcl_GetString to get a pointer to the byte array as a readonly value.
    bytes::Ptr{Cchar}

    # The number of bytes for object's string representation, not including the
    # terminating null.
    length::Cint

    # Object's type.  Always corresponds to the type of the object's internal
    # representation.  NULL indicates the object has no specific type and no
    # internal representation.
    typePtr::Ptr{Void}

    # Object's internal representation.  The value here is only valid for a
    # double precision floating-point object.  For other object types, this
    # field can be used to compute the offset of the object's internal
    # representation which is defined as an union in the C code.
    value::Cdouble
end

const __offset_of_refcount = fieldoffset(__TclObj, 1)
const __offset_of_bytes    = fieldoffset(__TclObj, 2)
const __offset_of_length   = fieldoffset(__TclObj, 3)
const __offset_of_type     = fieldoffset(__TclObj, 4)
const __offset_of_value    = fieldoffset(__TclObj, 5)

const TclObjTypePtr = fieldtype(__TclObj, :typePtr)

# Julia takes care of managing its objects so we just need to add a single
# reference for Julia for any Tcl object returned by Tcl library and make sure
# that the refrence count is decremented when the Julia object is finalized.
#
# The following methods correspond to the Tcl macros which are provided to
# increment and decrement a Tcl_Obj's reference count, and to test whether an
# object is shared (i.e. has reference count > 1).
#
# The reference count of a Tcl object is an `int` which is the first member of
# the Tcl_Obj structure and we directly address it using "unsafe" operations.

@static if __offset_of_refcount != 0
    error("it is assumed that refCount comes first in Tcl_Obj structure")
end

@inline __getrefcount(obj::TclObj)  = __getrefcount(obj.ptr)
@inline __incrrefcount(obj::TclObj) = __incrrefcount(obj.ptr)
@inline __decrrefcount(obj::TclObj) = __decrrefcount(obj.ptr)

@inline __isshared(obj::Union{TclObj,TclObjPtr}) =
    (__getrefcount(obj) > one(Cint))

@inline __getrefcount(objptr::TclObjPtr) = __peek(Cint, objptr)

@inline function __incrrefcount(objptr::TclObjPtr)
    ptr = Ptr{Cint}(objptr)
    __poke!(ptr, __peek(ptr) + one(Cint))
    return objptr
end

@inline function __decrrefcount(objptr::TclObjPtr)
    ptr = Ptr{Cint}(objptr)
    newrefcount = __peek(ptr) - one(Cint)
    if newrefcount ≥ 1
        __poke!(ptr, newrefcount)
    else
        ccall((:TclFreeObj, libtcl), Void, (TclObjPtr,), objptr)
    end
end

# These functions are to avoid overloading unsafe_load and unsafe_store.
@inline __peek(ptr::Ptr{T}, i::Integer) where {T} =
    unsafe_load(ptr + (i - 1)*sizeof(T))
@inline __peek(ptr::Ptr) = unsafe_load(ptr)
@inline __peek(::Type{T}, ptr::Ptr) where {T} = __peek(Ptr{T}(ptr))
@inline __peek(::Type{T}, ptr::Ptr, i::Integer) where {T} =
    __peek(Ptr{T}(ptr), i)

@inline __poke!(ptr::Ptr, args...) = unsafe_store!(ptr, args...)
@inline __poke!(::Type{T}, ptr::Ptr, args...) where {T} =
    __poke!(Ptr{T}(ptr), args...)

"""
```julia
__getobjtype(arg)
```

yields the address of a Tcl object type (`Tcl_ObjType*` in C).  Argument can be
the name of a registered Tcl type, a managed Tcl object or the address of a Tcl
object (must not be `C_NULL`).

"""
__getobjtype(obj::TclObj) = __getobjtype(obj.ptr)
__getobjtype(objptr::TclObjPtr) =
    __peek(TclObjTypePtr, objptr + __offset_of_type)
__getobjtype(name::StringOrSymbol) =
    ccall((:Tcl_GetObjType, Tcl.libtcl), TclObjTypePtr, (Cstring,), name)

const __bool_type    = Ref{Ptr{Void}}(0)
const __int_type     = Ref{Ptr{Void}}(0)
const __wideint_type = Ref{Ptr{Void}}(0)
const __double_type  = Ref{Ptr{Void}}(0)
const __list_type    = Ref{Ptr{Void}}(0)
const __string_type  = Ref{Ptr{Void}}(0)
const KnownTypes = Union{Void,Bool,Cint,Int64,Cdouble,String,List}
function __init_types(bynames::Bool = false)
    if bynames
        __int_type[]     = __getobjtype("int")
        __wideint_type[] = __getobjtype("wideint")
        if __wideint_type[] == C_NULL
            __wideint_type[] = __int_type[]
        end
        __double_type[]  = __getobjtype("double")
        __string_type[]  = C_NULL
        __list_type[]    = __getobjtype("list")
        __bool_type[] = __int_type[]
    else
        int_obj = TclObj(Cint(0))
        wideint_obj = TclObj(Int64(0))
        double_obj = TclObj(Cdouble(0))
        string_obj = TclObj("")
        list_obj = Tcl.list(int_obj, wideint_obj)
        bool_obj = TclObj(true)
        __int_type[]     = __getobjtype(int_obj)
        __wideint_type[] = __getobjtype(wideint_obj)
        __double_type[]  = __getobjtype(double_obj)
        __string_type[]  = __getobjtype(string_obj)
        __list_type[]    = __getobjtype(list_obj)
        __bool_type[]    = __getobjtype(bool_obj)
    end
end

__illegal_null_object_pointer() =
    tclerror("illegal NULL Tcl object pointer")

__illegal_null_string_pointer() =
    tclerror("illegal NULL C-string pointer")

"""
```julia
__ptr_to_string(strptr::Cstring)
````
or
```julia
__objptr_to_string(objptr::Ptr{Void})
```

yield the string representation corresponding to an address returned by a call
to a Tcl C function.  Here `strptr` is the address of a C-string while `objptr`
is assumed to be a pointer to a Tcl object.

This function is to be considered as *private*, the end-user should call the
`string` method on managed Tcl objects (of type `TclObj`).

See also: [`string`](@ref), [`__objptr_to_value`](@ref).

"""
__ptr_to_string(strptr::Cstring) =
    # In principle, `unsafe_string` will refuse to convert NULL to string.  So
    # no checks here.
    unsafe_string(strptr)

function __objptr_to_string(objptr::TclObjPtr)
    if objptr == C_NULL
        __illegal_null_object_pointer()
    end
    lenref = Ref{Cint}()
    strptr = ccall((:Tcl_GetStringFromObj, libtcl), Ptr{UInt8},
                   (TclObjPtr, Ptr{Cint}), objptr, lenref)
    if strptr == C_NULL
        tclerror("failed to retrieve string representation of Tcl object")
    end
    return unsafe_string(strptr, lenref[])
end

"""
```julia
__ptr_to_value(strptr::Cstring)
````
or
```julia
__objptr_to_value([T::DataType,] objptr::Ptr{Void})
````

yield the value corresponding to an address returned by a call to a Tcl C
function.  Here `strptr` is the address of a C-string while `objptr` is assumed
to be a pointer to a Tcl object.  For a Tcl object, the type `T` of the result
must correspond to the internal representation of the object.  If the type `T`
is omitted, it is retrieved in the object structure at the given address.

This function is to be considered as *private*, the end-user should call the
`getvalue` method on managed Tcl objects (of type `TclObj`).

See also: [`getvalue`](@ref), [`__objptr_to_string`](@ref).

"""
__objptr_to_value(objptr::Ptr{Void}) =
    __objptr_to_value(__objtype(objptr), objptr)

__ptr_to_value(strptr::Cstring) = unsafe_string(strptr)

__objptr_to_value(::Type{String}, objptr::Ptr{Void}) =
    __objptr_to_string(objptr)

for (T, f) in ((Cint, :Tcl_GetIntFromObj),
               (Clong, :Tcl_GetLongFromObj),
               (Int64, :Tcl_GetWideIntFromObj),
               (Cdouble, :Tcl_GetDoubleFromObj))
    # Avoid duplicates.
    if ((f == :Tcl_GetIntFromObj && (T == Clong || T == Int64)) ||
        (f == :Tcl_GetLongFromObj && T == Int64))
        continue
    end
    msg = "$f failed"
    tup = (f, libtcl)
    @eval begin

        function __objptr_to_value(::Type{$T}, objptr::Ptr{Void})
            ref = Ref{$T}()
            code = ccall($tup, Cint, (TclInterpPtr, TclObjPtr, Ptr{$T}),
                         C_NULL, objptr, ref)
            code == TCL_OK || tclerror($msg)
            return ref[]
        end

    end
end

function __objptr_to_value(::Type{Bool}, objptr::Ptr{Void})
    ref = Ref{Cint}() # a boolean is an int in C
    code = ccall((:Tcl_GetBooleanFromObj, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Ptr{Cint}),
                 C_NULL, objptr, ref)
    code == TCL_OK || tclerror("Tcl_GetBooleanFromObj failed ($code)")
    return (ref[] != zero(Cint))
end

"""
```julia
__ptr_to_object(strptr::Cstring)
````
or
```julia
__objptr_to_object([T::DataType,] objptr::Ptr{Void})
````

yield a managed Tcl object corresponding to an address returned by a call to a
Tcl C function.  Here `strptr` is the address of a C-string while `objptr` is
assumed to be a pointer to a Tcl object.  For a Tcl object, `T` is the type of
the internal representation of the object.  If the type `T` is omitted, it is
retrieved in the object struture at the given address.

This function should be considered as *private*.

See also: [`getvalue`](@ref), [`__objptr_to_string`](@ref).

"""
__ptr_to_object(strptr::Cstring) = # FIXME: ?????
    __objptr_to_object(String, __newobj(__ptr_to_string(strptr)))

__objptr_to_object(objptr::Ptr{Void}) =
    __objptr_to_object(__objtype(objptr), objptr)

__objptr_to_object(::Type{T}, objptr::Ptr{Void}) where {T<:KnownTypes} =
    TclObj{T}(objptr)

"""
```julia
__objtype(objptr::Ptr{Void})
````

yields the equivalent Julia type of the Tcl object at address `objptr`.

This function should be considered as *private*.

See also: [`Tcl.getvalue`](@ref), [`Tcl.getresult`](@ref).

"""
function __objtype(objptr::Ptr{Void})
    if objptr == C_NULL
        return Void
    else
        # `wideint` must be checked before `int` because they may be the same
        # on some machines
        typeptr = __getobjtype(objptr)
        if typeptr == __wideint_type[]
            return Int64
        elseif typeptr == __double_type[]
            return Cdouble
        elseif typeptr == __list_type[]
            return List
        elseif typeptr == __int_type[]
            return Cint
        elseif typeptr == __bool_type[]
            return Cint
        else
            return String
        end
    end
end
