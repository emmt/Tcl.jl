#
# objects.jl -
#
# Management of Tcl objects.
#
# Tcl memory management is such that Tcl_Panic is called whenever memory
# allocation fails causing the program to abort.  It is therefore not necessary
# to check for the reference returned by object creation functions as it can
# never be NULL.  This simplifies the code (no needs to report such errors or
# throw exceptions and then catch them, etc.).
#

# Extend base methods for objects.

Base.string(obj::TclObj) = __objptr_to(String, __objptr(obj))

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

# Finalizing the object is just a matter of decrementing its reference count.
__finalize(obj::TclObj) = Tcl_DecrRefCount(__objptr(obj))


"""
```julia
Tcl.getvalue(obj)
````

yields the value of a Tcl object.  The type of the result corresponds to
the internal representation of the object.

"""
getvalue(obj::TclObj{T}) where {T} = __objptr_to(T, __objptr(obj))


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
atomictype(T)
```

yields a sub-type of `AtomicType` indicating whether objects of type `T` are
atomic (that is always interpreted as a single list element) or not.

"""
atomictype(::Type{<:Iterables}) = NonAtomic
atomictype(::Type{TclObj{T}}) where T = atomictype(T)


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


"""
```julia
__newobj(value)
```

yields a pointer to a temporary Tcl object with given value.  This method may
throw an exception.

""" __newobj


# Booleans.
#
#     Tcl boolean is in fact stored as an `Cint` despite the fact that it is
#     possible to create boolean objects, they are retrieved as `Cint` objects.

TclObj(value::Bool) = TclObj{Bool}(__newobj(value))

atomictype(::Type{Bool}) = Atomic

__objptr(value::Bool) = __newobj(value)

__newobj(value::Bool) = Tcl_NewBooleanObj(value)


# Integers.
#
#     For each integer type, we choose the Tcl integer which is large enough to
#     store a value of that type.  Small unsigned integers may be problematic,
#     but not so much as the smallest Tcl integer type is `Cint` which is at
#     least 32 bits.

for Tj in (Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64)
    (Tc, f) = (sizeof(Tj) ≤ sizeof(Cint) ? (Cint, :Tcl_NewIntObj) :
               sizeof(Tj) ≤ sizeof(Clong) ? (Clong, :Tcl_NewLongObj) :
               (WideInt, :Tcl_NewWideIntObj))
    @eval begin

        TclObj(value::$Tj) = TclObj{$Tc}(__newobj(value))

        atomictype(::Type{$Tj}) = Atomic

        __objptr(value::$Tj) = __newobj(value)

        __newobj(value::$Tj) = $f(value)

    end

end


# Floats.
#
#     All floating point types, rationals and irrationals yield `Cdouble` Tcl
#     objects.

TclObj(value::FloatingPoint) = TclObj{Cdouble}(__newobj(value))

atomictype(::Type{<:FloatingPoint}) = Atomic

__objptr(value::FloatingPoint) = __newobj(value)

__newobj(value::Cdouble) = Tcl_NewDoubleObj(value)
__newobj(value::FloatingPoint) = __newobj(convert(Cdouble, value))


# Strings.
#
#     Julia strings and symbols are assumed to be Tcl strings.  Julia
#     characters are assumed to Tcl strings of length 1.  Strings may be split
#     in several arguments (hence they are non-atomic) while characters and
#     symbols are atomic.
#
#     There are two alternatives to create Tcl string objects:
#     `Tcl_NewStringObj` or `Tcl_NewUnicodeObj`.  After some testings (see my
#     notes), the following works correctly.  To build a Tcl object from a
#     Julia string, use `Ptr{UInt8}` instead of `Cstring` and provide the
#     number of bytes with `sizeof(str)`.


TclObj(x::Union{Char,Symbol,AbstractString}) = TclObj{String}(__newobj(x))

atomictype(::Type{<:Union{Char,Symbol}}) = Atomic
atomictype(::Type{<:AbstractString}) = NonAtomic

__objptr(x::Union{Char,Symbol,AbstractString}) = __newobj(x)

__newobj(x::Union{Char,Symbol}) = __newobj(string(x))
__newobj(str::AbstractString) = Tcl_NewStringObj(str)

__newstringobj(ptr::Ptr{T}, nbytes::Integer) where {T<:Byte} =
    Tcl_NewStringObj(ptr, nbytes)


# Nothing and nothing.
#
#     Nothing is loosely aliased to "" in Tcl.  Could also be an empty list.

TclObj(x::Nothing) = TclObj{Nothing}(__newobj(x))

atomictype(::Type{Nothing}) = Atomic

__objptr(x::Nothing) = __newobj(x)

__newobj(::Nothing) = __newobj("")


@static if false
# Unsupported objects.
#
#     These fallbacks are only meet for unsupported types.

TclObj(::T) where T = __unsupported_object_type(T)

atomictype(::Type{T}) where T = __unsupported_object_type(T)

__objptr(::T) where T = __unsupported_object_type(T)

__newobj(::T) where T = __unsupported_object_type(T)

__unsupported_object_type(::Type{T}) where T =
    Tcl.error("making a Tcl object for type $T is not supported")

end

#------------------------------------------------------------------------------


"""
```julia
__getobjtype(arg)
```

yields the address of a Tcl object type (`Tcl_ObjType*` in C).  Argument can be
a managed Tcl object or the address of a Tcl object (must not be `C_NULL`).

"""
__getobjtype(obj::TclObj) = __getobjtype(__objptr(obj))
__getobjtype(objptr::TclObjPtr) =
    __peek(TclObjTypePtr, objptr + __offset_of_type)

const __bool_type    = Ref{Ptr{Cvoid}}(0)
const __int_type     = Ref{Ptr{Cvoid}}(0)
const __wideint_type = Ref{Ptr{Cvoid}}(0)
const __double_type  = Ref{Ptr{Cvoid}}(0)
const __list_type    = Ref{Ptr{Cvoid}}(0)
const __string_type  = Ref{Ptr{Cvoid}}(0)
const KnownTypes = Union{Nothing,Bool,Cint,WideInt,Cdouble,String,List}
function __init_types(bynames::Bool = false)
    if bynames
        __int_type[]     = Tcl_GetObjType("int")
        __wideint_type[] = Tcl_GetObjType("wideint")
        if __wideint_type[] == C_NULL
            __wideint_type[] = __int_type[]
        end
        __double_type[]  = Tcl_GetObjType("double")
        __string_type[]  = C_NULL
        __list_type[]    = Tcl_GetObjType("list")
        __bool_type[] = __int_type[]
    else
        int_obj = TclObj(Cint(0))
        wideint_obj = TclObj(WideInt(0))
        double_obj = TclObj(Cdouble(0))
        string_obj = TclObj("")
        list_obj = list(int_obj, wideint_obj)
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
    Tcl.error("illegal NULL Tcl object pointer")

__illegal_null_string_pointer() =
    Tcl.error("illegal NULL C-string pointer")

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
__objptr_to(T::DataType, objptr::Ptr{Cvoid})
````

converts the Tcl object at address `objptr` into a value of type `T`.
See [`Tcl.getvar`](@ref) for details about how `T` is interpreted.

If reference `intptr` to Tcl interpreter is non NULL, it is used to retrieve an
error message if the conversion fails.

See also: [`Tcl.getvar`](@ref), [`Tcl.getvalue`](@ref).

"""
@inline __objptr_to(::Type{Any}, objptr::Ptr{Cvoid}) =
    __objptr_to(__objtype(objptr), objptr)

@inline __objptr_to(::Type{TclObj}, objptr::Ptr{Cvoid}) =
    TclObj{__objtype(objptr)}(objptr)

@inline function __objptr_to(::Type{String}, objptr::TclObjPtr) :: String
    ptr, len = Tcl_GetStringFromObj(objptr)
    if ptr == C_NULL
        Tcl.error("failed to retrieve string representation of Tcl object")
    end
    return unsafe_string(ptr, len)
end

@inline function __objptr_to(::Type{Char}, objptr::Ptr{Cvoid}) :: Char
    ptr, len = Tcl_GetStringFromObj(objptr)
    if ptr == C_NULL
        Tcl.error("failed to retrieve string representation of Tcl object")
    end
    if len != 1
        Tcl.error("failed to convert Tcl object to a single character")
    end
    return unsafe_string(ptr, 1)[1]
end

@inline function __objptr_to(::Type{Bool}, objptr::TclObjPtr) :: Bool
    status, value = Tcl_GetBooleanFromObj(__intptr(), objptr)
    if status != TCL_OK
        __contextual_error("failed to convert Tcl object to a boolean")
    end
    return value
end

# Find closest approximation for converting an object to an integer.
for Tj in (Int8, Int16, Int32, Int64, UInt8, UInt16, UInt32, UInt64)
    msg = "failed to convert Tcl object to an integer ($Tj)"
    for pass in 1:2,
        (f,Tc) in ((:Tcl_GetIntFromObj,     Cint),
                   (:Tcl_GetLongFromObj,    Clong),
                   (:Tcl_GetWideintFromObj, WideInt))
        if (pass == 1 && Tj == Tc) || (pass == 2 && sizeof(Tj) ≤ sizeof(Tc))
            # Exact match found or size large enough.
            result = (Tj == Tc ? :value : :(convert(Tj, value)))
            @eval @inline function __objptr_to(::Type{$Tj},
                                               objptr::TclObjPtr) :: $Tj
                status, value = $f(__intptr(), objptr)
                status == TCL_OK || __contextual_error($msg)
                return $result
            end
            break
        end
    end
end

@inline function __objptr_to(::Type{Cdouble}, objptr::TclObjPtr) :: Cdouble
    status, value = Tcl_GetDoubleFromObj(__intptr(), objptr)
    if status != TCL_OK
        __contextual_error("failed to convert Tcl object to a float")
    end
    return value
end

@inline function __objptr_to(::Type{T},
                             objptr::TclObjPtr) :: T where {T<:AbstractFloat}
    return convert(T, __objptr_to(Cdouble, objptr))
end

"""
```julia
__objtype(objptr::Ptr{Cvoid})
````

yields the equivalent Julia type of the Tcl object at address `objptr`.

This function should be considered as *private*.

See also: [`Tcl.getvalue`](@ref), [`Tcl.getresult`](@ref).

"""
@inline function __objtype(objptr::Ptr{Cvoid})
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
