#
# objects.jl -
#
# Management of Tcl objects.
#


# Extend base methods for objects.

# FIXME: A slight optimization is possible here because we know that
#        the object pointer cannot be NULL.
Base.string(obj::TclObj) = __objptr_to(String, obj.ptr)

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
getvalue(obj::TclObj{T}) where {T} = __objptr_to(T, obj.ptr)


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
const KnownTypes = Union{Void,Bool,Cint,WideInt,Cdouble,String,List}
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
        wideint_obj = TclObj(WideInt(0))
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
__ptr_to(T::DataType, strptr::Cstring)
````

converts a C-string (for instance, returned by a C function) into a Julia value
of type `T`.  If `T` is `Any` or `String`, a Julia string is returned, if `T`
is `TclObj` or `TclObj{String}` a managed Tcl object with a string value is
returned.

See also: [`string`](@ref), [`__objptr_to`](@ref).

"""
__ptr_to(::Type{String}, strptr::Cstring) =
    # In principle, `unsafe_string` will refuse to convert NULL to string.  So
    # no checks here.
    unsafe_string(strptr)

__ptr_to(::Type{Any}, strptr::Cstring) = __ptr_to(String, strptr::Cstring)

__ptr_to(::Type{<:Union{TclObj,TclObj{String}}}, strptr::Cstring) =
    TclObj{String}(__newobj(__ptr_to(String, strptr)))


"""

```julia
__objptr_to(T::DataType, [interp::TclInterp,] objptr::Ptr{Void})
````

converts the Tcl object at address `objptr` into a value of type `T`.
See [`Tcl.getvar`](@ref) for details about how `T` is interpreted.

If Tcl interpreter `interp` is specified, it is used to retrieve an
error message if the conversion fails.

See also: [`Tcl.getvar`](@ref), [`Tcl.getvalue`](@ref).

"""
__objptr_to(::Type{Any}, interp::TclInterp, objptr::Ptr{Void}) =
    __objptr_to(__objtype(objptr), interp, objptr)

__objptr_to(::Type{Any}, objptr::Ptr{Void}) =
    __objptr_to(__objtype(objptr), objptr)


__objptr_to(::Type{TclObj}, interp::TclInterp, objptr::Ptr{Void}) =
    TclObj{__objtype(objptr)}(objptr)

__objptr_to(::Type{TclObj}, objptr::Ptr{Void}) =
    TclObj{__objtype(objptr)}(objptr)


__objptr_to(::Type{String}, interp::TclInterp, objptr::Ptr{Void}) =
    __objptr_to(String, objptr)

function __objptr_to(::Type{String}, objptr::TclObjPtr)
    objptr != C_NULL || __illegal_null_object_pointer()
    lenref = Ref{Cint}()
    strptr = ccall((:Tcl_GetStringFromObj, libtcl), Ptr{UInt8},
                   (TclObjPtr, Ptr{Cint}), objptr, lenref)
    if strptr == C_NULL
        tclerror("failed to retrieve string representation of Tcl object")
    end
    return unsafe_string(strptr, lenref[])
end

__objptr_to(::Type{Char}, interp::TclInterp, objptr::Ptr{Void}) =
    __objptr_to(Char, objptr)

function __objptr_to(::Type{Char}, objptr::TclObjPtr)
    objptr != C_NULL || __illegal_null_object_pointer()
    lenref = Ref{Cint}()
    strptr = ccall((:Tcl_GetStringFromObj, libtcl), Ptr{UInt8},
                   (TclObjPtr, Ptr{Cint}), objptr, lenref)
    if strptr == C_NULL
        tclerror("failed to retrieve string representation of Tcl object")
    end
    if lenref[] != 1
        tclerror("failed to convert Tcl object to a single character")
    end
    return unsafe_string(strptr, 1)[1]
end

function __objptr_to(::Type{Bool}, interp::TclInterp,
                     objptr::TclObjPtr) :: Bool
    code, value = __get_boolean_from_obj(interp.ptr, objptr)
    code == TCL_OK || tclerror(interp)
    return (value != zero(value))
end

function __objptr_to(::Type{Bool}, objptr::TclObjPtr) :: Bool
    code, value = __get_boolean_from_obj(C_NULL, objptr)
    code == TCL_OK || tclerror("failed to convert Tcl object to a boolean")
    return (value != zero(value))
end

# Find closest approximation for converting an object to an integer.
for Tj in (Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64)
    msg = "failed to convert Tcl object to an integer ($Tj)"
    for pass in 1:2,
        (f,Tc) in ((:__get_int_from_obj,     Cint),
                   (:__get_long_from_obj,    Clong),
                   (:__get_wideint_from_obj, WideInt))
        if (pass == 1 && Tj == Tc) || (pass == 2 && sizeof(Tj) ≤ sizeof(Tc))
            # Exact match found or size large enough.
            result = (Tj == Tc ? :value : :(convert(Tj, value)))
            @eval begin

                function __objptr_to(::Type{$Tj}, interp::TclInterp,
                                     objptr::TclObjPtr) :: $Tj
                    code, value = $f(interp.ptr, objptr)
                    code == TCL_OK || tclerror(interp)
                    return $result
                end

                function __objptr_to(::Type{$Tj}, objptr::TclObjPtr) :: $Tj
                    code, value = $f(C_NULL, objptr)
                    code == TCL_OK || tclerror($msg)
                    return $result
                end

            end
            break
        end
    end
end

function __objptr_to(::Type{Cdouble}, interp::TclInterp,
                     objptr::TclObjPtr) :: Cdouble
    code, value = __get_double_from_obj(interp.ptr, objptr)
    code == TCL_OK || tclerror(interp)
    return value
end

function __objptr_to(::Type{Cdouble}, objptr::TclObjPtr) :: Cdouble
    code, value = __get_double_from_obj(C_NULL, objptr)
    code == TCL_OK || tclerror("failed to convert Tcl object to a float")
    return value
end

for T in subtypes(AbstractFloat)
    if T != Cdouble
        @eval begin

            function __objptr_to(::Type{$T}, interp::TclInterp,
                                 objptr::TclObjPtr) :: $T
                return convert($T, __objptr_to(Cdouble, interp, objptr))
            end

            function __objptr_to(::Type{$T}, objptr::TclObjPtr) :: $T
                return convert($T, __objptr_to(Cdouble, objptr))
            end

        end

    end
end

# Direct interface to Tcl library for all numerical types.
for (j,c,T) in ((:__get_boolean_from_obj, :Tcl_GetBooleanFromObj, Cint),
                (:__get_int_from_obj,     :Tcl_GetIntFromObj,     Cint),
                (:__get_long_from_obj,    :Tcl_GetLongFromObj,    Clong),
                (:__get_wideint_from_obj, :Tcl_GetWideIntFromObj, WideInt),
                (:__get_double_from_obj,  :Tcl_GetDoubleFromObj,  Cdouble))
    tup = (c, libtcl)
    @eval begin
        function $j(intptr::TclInterpPtr,
                    objptr::TclObjPtr) :: Tuple{Cint,$T}
            objptr != C_NULL || __illegal_null_object_pointer()
            valref = Ref{$T}()
            code = ccall($tup, Cint, (TclInterpPtr, TclObjPtr, Ptr{$T}),
                         intptr, objptr, valref)
            return code, valref[]
        end
    end
end

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
            return WideInt
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
