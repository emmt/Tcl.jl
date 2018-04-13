# Automatically named objects.

const __counter = Dict{String,Int}()

"""
    autoname(pfx = "jl_auto")

yields a unique name with given prefix.  The result is a string of the form
`pfx#` where `#` is a unique number for that prefix.
"""
function autoname(pfx::AbstractString = "jl_auto")
    global __counter
    n = get(__counter, pfx, 0) + 1
    __counter[pfx] = n
    return pfx*string(n)
end

#------------------------------------------------------------------------------
# Management of Tcl objects.

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

"""
```julia
__getobjtype(arg)
```

yields the address of a Tcl object type (`Tcl_ObjType*` in C).  Argument can be
the name of a registered Tcl type, a managed Tcl object or the address of a Tcl
object (must not be `C_NULL`).

"""
__getobjtype(obj::TclObj) = __getobjtype(obj.ptr)
__getobjtype(objptr::Ptr{Void}) = __peek(Ptr{Void}, objptr + __offset_of_type)
__getobjtype(name::StringOrSymbol) =
    ccall((:Tcl_GetObjType, Tcl.libtcl), Ptr{Void}, (Cstring,), name)

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
    tclerror("illegal NULL Tcl object pointer")

__illegal_null_string_pointer() =
    tclerror("illegal NULL C-string pointer")

"""
```julia
Tcl.getvalue(obj)
````

yields the value of a Tcl object.  The type of the result corresponds to
the internal representation of the object.

"""
getvalue(obj::TclObj{String}) = __ptr_to_string(obj.ptr)
getvalue(obj::TclObj{T}) where {T<:Union{Bool,Cint,Clong,Int64,Cdouble,List}} =
    __ptr_to_value(T, obj.ptr)

"""
```julia
__ptr_to_string(strptr::Cstring)
````
or
```julia
__ptr_to_string(objptr::Ptr{Void})
```

yield the string representation corresponding to an address returned by a call
to a Tcl C function.  Here `strptr` is the address of a C-string while `objptr`
is assumed to be a pointer to a Tcl object.

This function is to be considered as *private*, the end-user should call the
`string` method on managed Tcl objects (of type `TclObj`).

See also: [`string`](@ref), [`__ptr_to_value`](@ref).

"""
__ptr_to_string(strptr::Cstring) =
    # In principle, `unsafe_string` will refuse to convert NULL to string.  So
    # no checks here.
    unsafe_string(strptr)

function __ptr_to_string(objptr::TclObjPtr)
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
__ptr_to_value([T::DataType,] objptr::Ptr{Void})
````

yield the value corresponding to an address returned by a call to a Tcl C
function.  Here `strptr` is the address of a C-string while `objptr` is assumed
to be a pointer to a Tcl object.  For a Tcl object, the type `T` of the result
must correspond to the internal representation of the object.  If the type `T`
is omitted, it is retrieved in the object structure at the given address.

This function is to be considered as *private*, the end-user should call the
`getvalue` method on managed Tcl objects (of type `TclObj`).

See also: [`getvalue`](@ref), [`__ptr_to_string`](@ref).

"""
__ptr_to_value(objptr::Ptr{Void}) = __ptr_to_value(__objtype(objptr), objptr)

__ptr_to_value(strptr::Cstring) = unsafe_string(strptr)

__ptr_to_value(::Type{String}, objptr::Ptr{Void}) = __ptr_to_string(objptr)

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

        function __ptr_to_value(::Type{$T}, objptr::Ptr{Void})
            ref = Ref{$T}()
            code = ccall($tup, Cint, (TclInterpPtr, TclObjPtr, Ptr{$T}),
                         C_NULL, objptr, ref)
            code == TCL_OK || tclerror($msg)
            return ref[]
        end

    end
end

function __ptr_to_value(::Type{Bool}, objptr::Ptr{Void})
    ref = Ref{Cint}() # a boolean is an int in C
    code = ccall((:Tcl_GetBooleanFromObj, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Ptr{Cint}),
                 C_NULL, objptr, ref)
    code == TCL_OK || tclerror("Tcl_GetBooleanFromObj failed ($code)")
    return (ref[] != zero(Cint))
end

function __ptr_to_value(::Type{List}, listptr::Ptr{Void})
    if listptr == C_NULL
        return Array{Any}(0)
    end
    objc_ref = Ref{Cint}()
    objv_ref = Ref{Ptr{Ptr{Void}}}()
    code = ccall((:Tcl_ListObjGetElements, libtcl), Cint,
                 (Ptr{Void}, Ptr{Void}, Ptr{Cint}, Ptr{Ptr{Ptr{Void}}}),
                 C_NULL, listptr, objc_ref, objv_ref)
    code == TCL_OK || tclerror("Tcl_ListObjGetElements failed ($code)")
    objc = convert(Int, objc_ref[])
    objv = objv_ref[] # do not free this buffer (see Tcl doc.)
    v = Array{Any}(objc)
    if objc ≥ 1
        T = Ref{DataType}()
        for i in 1:objc
            v[i] = __ptr_to_value(__peek(objv, i))
            T[] = (i == 1 ? typeof(v[i]) :
                   __promote_elem_type(T[], typeof(v[i])))
        end
        if T[] != Any
            # A common type has been found, promote the vector to this common
            # type.
            return convert(Array{T[],1}, v)
        end
    end
    return v
end

# Rules for combining list element types and find a more precise common type
# than just `Any`.  Combinations of integers are promoted to the largest
# integer type and similarly for floats but mixture of floats and integers
# yield `Any`.

__promote_elem_type(::DataType, ::DataType) = Any

for T in (Integer, AbstractFloat)
    @eval begin

        function __promote_elem_type(::Type{T1},
                                     ::Type{T2}) where {T1<:$T,T2<:$T}
            return promote_type(T1, T2)
        end

        function __promote_elem_type(::Type{Vector{T1}},
                                     ::Type{Vector{T2}}) where {T1<:$T,
                                                                T2<:$T}
            return Vector{promote_type(T1, T2)}
        end

    end
end

__promote_elem_type(::Type{String}, ::Type{String}) = String

__promote_elem_type(::Type{Vector{String}}, ::Type{Vector{String}}) =
    Vector{String}

"""
```julia
__ptr_to_object(strptr::Cstring)
````
or
```julia
__ptr_to_object([T::DataType,] objptr::Ptr{Void})
````

yield a managed Tcl object corresponding to an address returned by a call to a
Tcl C function.  Here `strptr` is the address of a C-string while `objptr` is
assumed to be a pointer to a Tcl object.  For a Tcl object, `T` is the type of
the internal representation of the object.  If the type `T` is omitted, it is
retrieved in the object struture at the given address.

This function should be considered as *private*.

See also: [`getvalue`](@ref), [`__ptr_to_string`](@ref).

"""
__ptr_to_object(strptr::Cstring) = # FIXME: ?????
    __ptr_to_object(String, __newobj(__ptr_to_string(strptr)))

__ptr_to_object(objptr::Ptr{Void}) = __ptr_to_object(__objtype(objptr), objptr)

__ptr_to_object(::Type{T}, objptr::Ptr{Void}) where {T<:KnownTypes} =
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


# Lists.
#
#     Iterables like vectors and tuples yield lists.  No arguments, yield empty
#     lists.
#
#     FIXME: There should be a way to automatically make lists from iterables
#            and to convert multi-dimensional arrays into lists of lists.

TclObj() = TclObj{List}(__newlistobj())

__newobj() = __newlistobj()

TclObj(itr::Iterables) = TclObj{List}(__newobj(itr))

function __newobj(itr::Iterables) ::TclObjPtr
    listptr = __newlistobj()
    try
        for val in itr
            __lappend!(listptr, val)
        end
    catch ex
        __decrrefcount(listptr)
        rethrow(ex)
    end
    return listptr
end


"""
```julia
__newlistobj(itr)
```

yields a pointer to a new Tcl list object whose items are taken from
the iterable collection `itr`.

```julia
__newlistobj(args...; kwds...)
```

yields a pointer to a new Tcl list object whose leading items are taken from
`args...` and to which are appended the `(key,val)` pairs from `kwds...` so as
to mimic Tk options.

Beware that the returned object is not managed and has a zero reference count.
The caller is reponsible of taking care of that.

"""
function __newlistobj()
    objptr = ccall((:Tcl_NewListObj, libtcl), TclObjPtr,
                   (Cint, Ptr{TclObjPtr}), 0, C_NULL)
    if objptr == C_NULL
        tclerror("failed to create an empty Tcl list")
    end
    return objptr
end

function __newlistobj(args...; kwds...) ::TclObjPtr
    listptr = __newlistobj()
    try
        for arg in args
            __lappend!(listptr, arg)
        end
        for (key, val) in kwds
            __lappendoption!(listptr, key, val)
        end
    catch ex
        __decrrefcount(listptr)
        rethrow(ex)
    end
    return listptr
end

__appendlistelement!(listptr::TclObjPtr, itemptr::TclObjPtr) =
    ccall((:Tcl_ListObjAppendElement, libtcl),
          Cint, (TclInterpPtr, TclObjPtr, TclObjPtr), C_NULL, listptr, itemptr)

function __lappend!(listptr::TclObjPtr, item)
    code = __appendlistelement!(listptr, __objptr(item))
    if code != TCL_OK
        tclerror("failed to append a new item to the Tcl list")
    end
    nothing
end

__lappendoption!(listptr::TclObjPtr, key::Symbol, val) =
    __lappendoption!(listptr, string(key), val)

function __lappendoption!(listptr::TclObjPtr, key::String, val)
    option = "-"*(length(key) ≥ 1 && key[1] == '_' ? key[2:end] : key)
    code = __appendlistelement!(listptr, __newobj(option))
    if code == TCL_OK
        code = __appendlistelement!(listptr, __objptr(val))
    end
    if code != TCL_OK
        tclerror("failed to append a new option to the Tcl list")
    end
    nothing
end


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

function __newstringobj(ptr::Ptr{T}, nbytes::Integer) where {T<:Byte}
    objptr = ccall((:Tcl_NewStringObj, libtcl), TclObjPtr,
                   (Ptr{T}, Cint), ptr, nbytes)
    if objptr == C_NULL
        tclerror("failed to create a Tcl string object")
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
# List of objects.

"""
```julia
list(args...; kwds...)
```

yields a list of Tcl objects consisting of the one object per argument
`args...` (in the same order as they appear) and then followed by two objects
per keyword, say `key=val`, in the form `-key`, `val` (note the hyphen in front
of the keyword name).  To allow for option names that are Julia keywords, a
leading underscore is stripped, if any, in `key`.

"""
list(args...; kwds...) = TclObj{List}(__newlistobj(args...; kwds...))

Base.length(lst::TclObj{List}) = llength(lst)
Base.push!(lst::TclObj{List}, args...; kwds...) =
    lappend!(lst, args...; kwds...)

function llength(lst::TclObj{List}) :: Int
    len = Ref{Cint}(0)
    code = ccall((:Tcl_ListObjLength, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Ptr{Cint}),
                 C_NULL, lst.ptr, len)
    code == TCL_OK || tclerror("failed to query length of list")
    return len[]
end


"""
```julia
lappend!(lst, args...; kwds...)
```

appends to the list `lst` of Tcl objects one object per argument `args...` (in
the same order as they appear) and then followed by two objects per keyword,
say `key=val`, in the form `-key`, `val` (note the hyphen in front of the
keyword name).  To allow for option names that are Julia keywords, a leading
underscore is stripped, if any, in `key`; for instance:

```julia
lappend!(lst, _in="something")
```

appends `"-in"` and `something` to the list `lst`.

"""
function lappend!(list::TclObj{List}, args...; kwds...)
    listptr = list.ptr
    for arg in args
        __lappend!(listptr, arg)
    end
    for (key, val) in kwds
        __lappendoption!(listptr, key, val)
    end
    return list
end

function lappendoption!(list::TclObj{List}, key::Name, val)
    __lappendoption!(list.ptr, __string(key), val)
    return list
end

#------------------------------------------------------------------------------
# Management of Tcl interpreters.

"""
When Tcl package is imported, an initial interpreter is created which can be
retrieved by:

```julia
interp = Tcl.getinterp()
```

A new Tcl interpreter can also be created by the command:

```julia
interp = TclInterp()
```

The resulting object can be used as a function to evaluate a Tcl script, for
instance:

```julia
interp("set x 42")
```

which yields the result of the script (here the string `"42"`).  An alternative
syntax is:

```
interp("set", "x", 42)
```

which yields the value `42`.  See methods [`Tcl.evaluate`](@ref) or
[`tcleval`](@ref) for more details about script evaluation.

The object can also be used as an array to access global Tcl variables (the
variable name can be specified as a string or as a symbol):

```julia
interp["x"]          # yields value of variable "x"
interp[:tcl_version] # yields version of Tcl
interp[:x] = 33      # set the value of "x" and yields its value
```

The Tcl interpreter is initialized and will be deleted when no longer in use.
If Tk has been properly installed, then:

```julia
interp("package require Tk")
```

should load Tk extension and create the "." toplevel Tk window.  But see
`tkstart` method to load Tk.

"""
function TclInterp(permanent::Bool=false)
    ptr = ccall((:Tcl_CreateInterp, libtcl), Ptr{Void}, ())
    ptr != C_NULL || tclerror("unable to create Tcl interpreter")
    obj = TclInterp(ptr)
    if ! permanent
        __preserve(ptr)
        finalizer(obj, __finalize)
    end
    code = ccall((:Tcl_Init, libtcl), Cint, (Ptr{Void},), ptr)
    code == TCL_OK || tclerror("unable to initialize Tcl interpreter")
    return obj
end

function __finalize(interp::TclInterp)
    # According to Tcl doc. Tcl_Release should be finally called after
    # Tcl_DeleteInterp.
    __deleteinterp(interp)
    __release(interp.ptr)
end

(interp::TclInterp)(args...; kwds...) = evaluate(interp, args...; kwds...)

isdeleted(interp::TclInterp) =
    ccall((:Tcl_InterpDeleted, libtcl), Cint,
          (TclInterpPtr,), interp.ptr) != zero(Cint)

isactive(interp::TclInterp) =
    ccall((:Tcl_InterpActive, libtcl), Cint,
          (TclInterpPtr,), interp.ptr) != zero(Cint)

__preserve(ptr::Ptr{Void}) =
    ccall((:Tcl_Preserve, libtcl), Void, (Ptr{Void},), ptr)

__release(ptr::Ptr{Void}) =
    ccall((:Tcl_Release, libtcl), Void, (Ptr{Void},), ptr)

__deleteinterp(interp::TclInterp) =
    ccall((:Tcl_DeleteInterp, libtcl), Void, (TclInterpPtr,), interp.ptr)


#------------------------------------------------------------------------------
# Evaluation of Tcl scripts.

"""
```julia
Tcl.setresult([interp,] args...) -> nothing
```

set result stored in Tcl interpreter `interp` or in the initial interpreter if
this argument is omitted.

"""
setresult() = setresult(getinterp())
setresult(arg) = setresult(getinterp(), arg)
setresult(args...) = setresult(getinterp(), args...)
setresult(interp::TclInterp) = __setresult(interp, __objptr())
setresult(interp::TclInterp, args...) = setresult(interp, __newlistobj(args))
setresult(interp::TclInterp, arg) = __setresult(interp, __objptr(arg))

# To set Tcl interpreter result, we can call `Tcl_SetObjResult` for any object,
# or `Tcl_SetResult` but only for string results with no embedded nulls.  There
# may be a slight advantage for calling `Tcl_SetResult` with non-volatile
# strings as copies are avoided.  Julia strings are immutable but I am not sure
# that they are non-volatile, so I prefer to not try using `Tcl_SetResult` and
# rather use `Tcl_SetObjResult` for any object.
__setresult(interp::TclInterp, objptr::TclObjPtr) =
    ccall((:Tcl_SetObjResult, libtcl), Void, (TclInterpPtr, TclObjPtr),
          interp.ptr, objptr)

@static if false
    # The code for strings (taking care of embedded nulls and using
    # `Tcl_SetResult` if possible) is written below for reference but not
    # compiled.
    function __setresult(interp::TclInterp, str::AbstractString, volatile::Bool)
        ptr = Base.unsafe_convert(Ptr{Cchar}, str)
        nbytes = sizeof(str)
        if Base.containsnul(ptr, nbytes)
            # String has embedded NULLs, wrap it into a temporary object.
            temp = __incrrefcount(__newstringobj(ptr, nbytes))
            ccall((:Tcl_SetObjResult, libtcl), Void, (TclInterpPtr, TclObjPtr),
                  interp.ptr, temp)
            __decrrefcount(temp)
        else
            ccall((:Tcl_SetResult, libtcl), Void,
                  (TclInterpPtr, Ptr{Cchar}, Ptr{Void}),
                  interp.ptr, ptr, (volatile ? TCL_VOLATILE : TCL_STATIC))
        end
    end
end

"""
```julia
Tcl.getresult([T,][interp])
```

yields the current result stored in Tcl interpreter `interp` or in the initial
interpreter if this argument is omitted.  If optional argument `T` is omitted,
the type of the returned value reflects that of the internal representation of
the result stored in Tcl interpreter; otherwise, `T` can be `String` to get the
string representation of the result or `TclObj` to get a managed Tcl object.  `

"""
getresult() = getresult(getinterp())

getresult(::Type{String}, interp::TclInterp) =
    __ptr_to_string(__getobjresult(interp))

getresult(::Type{TclObj}, interp::TclInterp) =
    __ptr_to_object(__getobjresult(interp))

getresult(interp::TclInterp) =
    __ptr_to_value(__getobjresult(interp))

# Tcl_GetStringResult calls Tcl_GetObjResult, so we only interface to this
# latter function.  Incrementing the reference count of the result is only
# needed if we want to keep a long-term reference to it (__ptr_to_object takes
# care of that).
__getobjresult(interp::TclInterp) =
    ccall((:Tcl_GetObjResult, libtcl), Ptr{Void}, (TclInterpPtr,), interp.ptr)

"""
```julia
tcleval([T,][interp,], arg0, args...; kwds...)
```
or
```julia
Tcl.evaluate([T,][interp,], arg0, args...; kwds...)
```

evaluate Tcl script or command with interpreter `interp` (or in the initial
interpreter if this argument is omitted).  If optional argument `T` is omitted,
the type of the returned value reflects that of the internal representation of
the result of the script; otherwise, `T` can be `String` to get the string
representation of the result of the script or `TclObj` to get a managed Tcl
object whose value is the result of the script.

If only `arg0` is present, it may be a `TclListObj` which is evaluated as a
single Tcl command; otherwise, `arg0` is evaluated as a Tcl script and may be
anything, like a string or a symbol, that can be converted into a `TclObj`.

If keywords or other arguments than `arg0` are present, they are used to build
a list of Tcl objects which is evaluated as a single command.  Any keyword, say
`key=val`, is automatically converted in the pair of arguments `-key` `val` in
this list (note the hyphen before the keyword name).  All keywords appear at
the end of the list in unspecific order.

Use `tcltry` if you want to avoid throwing errors and `Tcl.getresult` to
retrieve the result.

"""
evaluate(args...; kwds...) = evaluate(getinterp(), args...; kwds...)

evaluate(::Type{T}, args...; kwds...) where {T} =
    evaluate(T, getinterp(), args...; kwds...)

function evaluate(interp::TclInterp, args...; kwds...)
    tcltry(interp, args...; kwds...) == TCL_OK || tclerror(interp)
    return getresult(interp)
end

function evaluate(::Type{T}, interp::TclInterp, args...; kwds...) where {T}
    tcltry(interp, args...; kwds...) == TCL_OK || tclerror(interp)
    return getresult(T, interp)
end

const tcleval = evaluate

"""
```julia
tcltry([interp,], args...; kwds...) -> code
```

evaluates Tcl script or command with interpreter `interp` (or in the initial
interpreter if this argument is omitted) and return a code like `TCL_OK` or
`TCL_ERROR` indicating whether the script was successful.  The result of the
script can be retrieved with `Tcl.getresult`.  See `tcleval` for a description
of the interpretation of arguments `args...` and keywords `kwds...`.

"""
tcltry(args...; kwds...) = tcltry(getinterp(), args...; kwds...)

# This version gets called when there are any keywords or when zero or more
# than one argument.
function tcltry(interp::TclInterp, args...; kwds...)
    if length(args) < 1
        tclerror("expecting at least one argument")
    end
    return __evallist(interp, __newlistobj(args...; kwds...))
end

tcltry(interp::TclInterp, script::TclObj{List}) =
    __evallist(interp, script.ptr)

tcltry(interp::TclInterp, script) = __eval(interp, __objptr(script))

# FIXME: I do not understand this
#function tcltry(interp::TclInterp, script)
#    __currentinterpreter[] = interp
#    try
#        return __eval(interp, __objptr(script))
#    finally
#        __currentinterpreter[] = __initialinterpreter[]
#    end
#end

# We use `Tcl_EvalObjEx` and not `Tcl_EvalEx` to evaluate a script
# because the script may contain embedded nulls.

@inline function __eval(interp::TclInterp, objptr::TclObjPtr)
    flags = TCL_EVAL_GLOBAL
    if __getrefcount(objptr) < 1
        # For a temporary object there is no needs to compile the script.
        flags |= TCL_EVAL_DIRECT
    end
    return ccall((:Tcl_EvalObjEx, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Cint),
                 interp.ptr, objptr, flags)
end

function __evallist(interp::TclInterp, listptr::TclObjPtr)
    flags = TCL_EVAL_GLOBAL
    objc = Ref{Cint}(0)
    objv = Ref{Ptr{TclObjPtr}}(C_NULL)
    code = ccall((:Tcl_ListObjGetElements, libtcl), Cint,
                 (TclInterpPtr, TclObjPtr, Ptr{Cint}, Ptr{Ptr{TclObjPtr}}),
                 interp.ptr, listptr, objc, objv)
    if code == TCL_OK
        code = ccall((:Tcl_EvalObjv, libtcl), Cint,
                     (TclInterpPtr, Cint, Ptr{TclObjPtr}, Cint),
                     interp.ptr, objc[], objv[], flags)
    end
    return code
end

#------------------------------------------------------------------------------
# Initial Tcl interpreter.

# Many things do not work properly (e.g. freeing a Tcl object yield a
# segmentation fault) if no interpreter has been created, so we always create
# an initial Tcl interpreter.
const __initialinterpreter = Ref{TclInterp}()

# Interpreter for callbacks and objects which need a Tcl interpreter.
const __currentinterpreter = Ref{TclInterp}()

"""
    Tcl.getinterp()

yields the initial Tcl interpreter which is used by default by many methods.
An argument can be provided:

    Tcl.getinterp(w)

yields the Tcl interpreter for widget `w`.

"""
getinterp() = __initialinterpreter[]


#------------------------------------------------------------------------------
# Exceptions

"""
    tclerror(arg)

throws a `TclError` exception, argument `arg` can be the error message as a
string or a Tcl interpreter (in which case the error message is assumed to be
the current result of the Tcl interpreter).

"""
tclerror(msg::AbstractString) = throw(TclError(string(msg)))
tclerror(interp::TclInterp) = tclerror(getresult(String, interp))

"""
    geterrmsg(ex)

yields the error message associated with exception `ex`.

"""
geterrmsg(ex::Exception) = sprint(io -> showerror(io, ex))

#------------------------------------------------------------------------------
# Processing Tcl/Tk events.  The function `doevents` must be repeatedly
# called too process events when Tk is loaded.

"""
    Tcl.resume()

resumes or starts the processing of Tcl/Tk events.  This manages to repeatedly
call function `Tcl.doevents`.  The method `Tcl.suspend` can be called to
suspend the processing of events.

Calling `Tcl.resume` is mandatory when Tk extension is loaded.  Thus:

    Tcl.evaluate(interp, "package require Tk")
    Tcl.resume()

is the recommended way to load Tk package.  Alternatively:

    Tcl.tkstart(interp)

can be called to do that.

"""
function resume()
    global __timer
    if ! (isdefined(:__timer) && isopen(__timer))
        __timer = Timer(doevents, 0.1, 0.01)
    end
end

"""
    Tcl.suspend()

suspends the processing of Tcl/Tk events for all interpreters.  The method
`Tcl.resume` can be called to resume the processing of events.

"""
function suspend()
    global __timer
    if isdefined(:__timer) && isopen(__timer)
        close(__timer)
    end
end

"""
    Tcl.doevents(flags = TCL_DONT_WAIT|TCL_ALL_EVENTS)

processes Tcl/Tk events for all interpreters.  Normally this is automatically
called by the timer set by `Tcl.resume`.

"""
doevents(::Timer) = doevents()

function doevents(flags::Integer = TCL_DONT_WAIT|TCL_ALL_EVENTS)
    while ccall((:Tcl_DoOneEvent, libtcl), Cint, (Cint,), flags) != 0
    end
end

#------------------------------------------------------------------------------
# Dealing with Tcl variables.

const VARIABLE_FLAGS = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG

"""
```julia
Tcl.getvar([T,][interp,] name1 [,name2])
```

yields the value of the global variable `name1` or `name1(name2)` in Tcl
interpreter `interp` or in the initial interpreter if this argument is omitted.

If optional argument `T` is omitted, the type of the returned value reflects
that of the Tcl variable; otherwise, `T` can be `String` to get the string
representation of the value or `TclObj` to get a managed Tcl object.

See also: [`Tcl.exists`](@ref), [`Tcl.setvar`](@ref), [`Tcl.unsetvar`](@ref).

"""
getvar(args...) = getvar(getinterp(), args...)

getvar(::Type{T}, args...) where {T} = getvar(T, getinterp(), args...)

function getvar(interp::TclInterp, name::Name)
    ptr = __getvar(interp, name, C_NULL, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __ptr_to_value(ptr)
end

function getvar(::Type{TclObj}, interp::TclInterp, name::Name)
    ptr = __getvar(interp, name, C_NULL, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __ptr_to_object(ptr)
end

function getvar(::Type{String}, interp::TclInterp, name::Name)
    ptr = __getvar(interp, name, C_NULL, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __ptr_to_string(ptr)
end

function getvar(interp::TclInterp, name1::Name, name2::Name)
    ptr = __getvar(interp, name1, name2, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __ptr_to_value(ptr)
end

function getvar(::Type{TclObj}, interp::TclInterp, name1::Name, name2::Name)
    ptr = __getvar(interp, name1, name2, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __ptr_to_object(ptr)
end

function getvar(::Type{String}, interp::TclInterp, name1::Name, name2::Name)
    ptr = __getvar(interp, name1, name2, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __ptr_to_string(ptr)
end

# Tcl_GetVar would yield an incorrect result if the variable value has embedded
# nulls and symbol Tcl_ObjGetVar2Ex does not exist in the library (despite what
# says the doc.).  Hence we always use Tcl_ObjGetVar2 which may require to
# temporarily convert the variable name into a string object.  There is no loss
# of performances as it turns out that Tcl_GetVar, Tcl_GetVar2 and
# Tcl_ObjGetVar2Ex all call Tcl_ObjGetVar2.
#
# Since all arguments are passed as pointers to Tcl object, we have to take
# care of correctly unreference temporary objects.  As far as possible we
# try to avoid the ovehead of the `try ... catch ... finally` statements.

function __getvar(interp::TclInterp, name1::Name,
                  name2::TclObj{String}, flags::Integer)
    return __getvar(interp, name1, name2.ptr, flags)
end

function __getvar(interp::TclInterp, name1::Name,
                  name2::StringOrSymbol, flags::Integer)
    name2ptr = __incrrefcount(__newobj(name2))
    try
        return __getvar(interp, name1, name2ptr, flags)
    finally
        __decrrefcount(name2ptr)
    end
end

function __getvar(interp::TclInterp, name1::TclObj{String},
                  name2ptr::Ptr{Void}, flags::Integer)
    return __getvar(interp, name1.ptr, name2ptr, flags)
end

function __getvar(interp::TclInterp, name1::StringOrSymbol,
                  name2ptr::Ptr{Void}, flags::Integer)

    name1ptr = __incrrefcount(__newobj(name1))
    result = __getvar(interp, name1ptr, name2ptr, flags)
    __decrrefcount(name1ptr)
    return result
end

function __getvar(interp::TclInterp, name1ptr::Ptr{Void},
                  name2ptr::Ptr{Void}, flags::Integer)
    return ccall((:Tcl_ObjGetVar2, libtcl), Ptr{Void},
                 (Ptr{Void}, Ptr{Void}, Ptr{Void}, Cint),
                 interp.ptr, name1ptr, name2ptr, flags)
end

"""
```julia
Tcl.setvar([interp,] name1, [name2,] value)
```

set global variable `name1` or `name1(name2)` to be `value` in Tcl interpreter
`interp` or in the initial interpreter if this argument is omitted.  The result
is `nothing`.

See [`Tcl.getvar`](@ref) for details about allowed variable names.

See also: [`Tcl.getvar`](@ref), [`Tcl.exists`](@ref), [`Tcl.unsetvar`](@ref).

"""
setvar(args...) = setvar(getinterp(), args...)

function setvar(interp::TclInterp, name::Name, value)
    ptr = __setvar(interp, name, value, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return nothing
end

function setvar(interp::TclInterp, name1::Name, name2::Name, value)
    ptr = __setvar(interp, name1, name2, value, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return nothing
end

# Like Tcl_ObjGetVar2Ex, Tcl_ObjSetVar2Ex may be not found in library so we
# avoid using it.  In fact, it turns out that Tcl_SetVar, Tcl_SetVar2 and
# Tcl_ObjSetVar2Ex call Tcl_ObjGetVar2 to do their stuff, so we only use
# Tcl_ObjGetVar2 with no loss of performances. as it turns out that Tcl_SetVar
# calls Tcl_ObjGetVar2.
#
# Same remarks as for `__getvar` about correctly unreferencing temporary
# objects.

function __setvar(interp::TclInterp, name::TclObj{String},
                  value, flags::Integer)
    return __setvar(interp, name.ptr, C_NULL, __objptr(value), flags)
end

function __setvar(interp::TclInterp, name::StringOrSymbol,
                  value, flags::Integer)
    nameptr = C_NULL
    try
        nameptr = __incrrefcount(__newobj(name))
        return __setvar(interp, nameptr, C_NULL, __objptr(value), flags)
    finally
        if nameptr != C_NULL
            __decrrefcount(nameptr)
        end
    end
end

function __setvar(interp::TclInterp, name1::TclObj{String},
                  name2::TclObj{String}, value, flags::Integer)
    return __setvar(interp, name1.ptr, name2.ptr, __objptr(value), flags)
end

function __setvar(interp::TclInterp, name1::TclObj{String},
                  name2::StringOrSymbol, value, flags::Integer)
    name2ptr = C_NULL
    try
        name2ptr = __incrrefcount(__newobj(name2))
        return __setvar(interp, name1.ptr, name2ptr, __objptr(value), flags)
    finally
        if name2ptr != C_NULL
            __decrrefcount(name2ptr)
        end
    end
end

function __setvar(interp::TclInterp, name1::StringOrSymbol,
                  name2::TclObj{String}, value, flags::Integer)
    name1ptr = C_NULL
    try
        name1ptr = __incrrefcount(__newobj(name1))
        return __setvar(interp, name1ptr, name2.ptr, __objptr(value), flags)
    finally
        if name1ptr != C_NULL
            __decrrefcount(name1ptr)
        end
    end
end

function __setvar(interp::TclInterp, name1::StringOrSymbol,
                  name2::StringOrSymbol, value, flags::Integer)
    name1ptr = C_NULL
    name2ptr = C_NULL
    try
        name1ptr = __incrrefcount(__newobj(name1))
        name2ptr = __incrrefcount(__newobj(name2))
        return __setvar(interp, name1ptr, name2ptr, __objptr(value), flags)
    finally
        if name1ptr != C_NULL
            __decrrefcount(name1ptr)
        end
        if name2ptr != C_NULL
            __decrrefcount(name2ptr)
        end
    end
end

function __setvar(interp::TclInterp, name1ptr::Ptr{Void},
                  name2ptr::Ptr{Void}, valueptr::Ptr{Void}, flags::Integer)
    return ccall((:Tcl_ObjSetVar2, libtcl), TclObjPtr,
                 (TclInterpPtr, TclObjPtr, TclObjPtr, TclObjPtr, Cint),
                 interp.ptr, name1ptr, name2ptr, valueptr, flags)
end


"""
```julia
Tcl.unsetvar([interp,] name1 [,name2]; nocomplain=false)
```

deletes global variable `name1` or `name1(name2)` in Tcl interpreter `interp`
or in the initial interpreter if this argument is omitted.

Keyword `nocomplain` can be set true to ignore errors.

See also: [`Tcl.getvar`](@ref), [`Tcl.exists`](@ref), [`Tcl.setvar`](@ref).

"""
unsetvar(args...; kwds...) = unsetvar(getinterp(), args...; kwds...)

function unsetvar(interp::TclInterp, name::Name; nocomplain::Bool=false)
    flags = (nocomplain ? TCL_GLOBAL_ONLY : (TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG))
    code = __unsetvar(interp, __string(name), flags)
    if code != TCL_OK && ! nocomplain
        tclerror(interp)
    end
    return nothing
end

function unsetvar(interp::TclInterp, name1::Name, name2::Name;
                  nocomplain::Bool=false)
    flags = (nocomplain ? TCL_GLOBAL_ONLY : (TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG))
    code = __unsetvar(interp, __string(name1), __string(name2), flags)
    if code != TCL_OK && ! nocomplain
        tclerror(interp)
    end
    return nothing
end

# `TclUnsetVarObj2` would be the function to call here but, unfortunately, only
# `Tcl_UnsetVar` and `Tcl_UnsetVar2` are available which both require strings
# for the variable name parts.

function __unsetvar(interp::TclInterp, name::String, flags::Integer) :: Cint
    if (ptr = __cstring(name)[1]) != C_NULL
        code = ccall((:Tcl_UnsetVar, libtcl), Cint,
                     (TclInterpPtr, Ptr{Cchar}, Cint),
                     interp.ptr, ptr, flags)
    else
        code = __eval(interp, __newobj("unset {$name}"))
    end
    return code
end

function __unsetvar(interp::TclInterp, name1::String, name2::String,
                    flags::Integer) :: Cint
    if ((ptr1 = __cstring(name1)[1]) != C_NULL &&
        (ptr2 = __cstring(name2)[1]) != C_NULL)
        code = ccall((:Tcl_UnsetVar2, libtcl), Cint,
                     (TclInterpPtr, Ptr{Cchar}, Ptr{Cchar}, Cint),
                     interp.ptr, ptr1, ptr2, flags)
    else
        code = __eval(interp, __newobj("unset {$name1($name2)}"))
    end
    return code
end


"""
`julia
Tcl.exists([interp,] name1 [, name2])
```

checks whether global variable `name1` or `name1(name2)` is defined in Tcl
interpreter `interp` or in the initial interpreter if this argument is omitted.

See also: [`Tcl.getvar`](@ref), [`Tcl.setvar`](@ref), [`Tcl.unsetvar`](@ref).

"""
exists(args...) = exists(getinterp(), args...)

function exists(interp::TclInterp, name::Name)
    return (__getvar(interp, name, C_NULL, TCL_GLOBAL_ONLY) != C_NULL)
end

function exists(interp::TclInterp, name1::Name, name2::Name)
    return (__getvar(interp, name1, name2, TCL_GLOBAL_ONLY) != C_NULL)
end

"""
```julia
__string(str)
```

yields a `String` instance of `str`.

"""
__string(str::String) = str
__string(str::Union{AbstractString,Symbol,TclObj{String}}) = string(str)

"""
```julia
__cstring(str) -> ptr, siz
```

checks whether `str` is a valid C-string (i.e., has no embedded nulls)
and yields its base address and size.  If `str` is not eligible as a C string,
`(Ptr{Cchar}(0), 0)` is returned.

"""
function __cstring(str::String)
    ptr, siz = Base.unsafe_convert(Ptr{Cchar}, str), sizeof(str)
    if Base.containsnul(ptr, siz)
        ptr, siz = Ptr{Cchar}(0), zero(siz)
    end
    return ptr, siz
end

#------------------------------------------------------------------------------
# Implement callbacks.

# Dictionary of objects shared with Tcl to make sure they are not garbage
# collected until Tcl deletes their reference.
const __references = Dict{Any,Int}()

function preserve(obj)
    __references[obj] = get(__references, obj, 0) + 1
end

function release(obj)
    if haskey(__references, obj)
        if __references[obj] > 1
            __references[obj] -= 1
        else
            pop!(__references, obj)
        end
    end
    nothing
end

const __releaseobject_ref = Ref{Ptr{Void}}() # will be set by __init__
function __releaseobject(ptr::Ptr{Void}) :: Void
    release(unsafe_pointer_to_objref(ptr))
end

const __evalcommand_ref = Ref{Ptr{Void}}() # will be set by __init__
function __evalcommand(fptr::Ptr{Void}, iptr::Ptr{Void},
                       argc::Cint, argv::Ptr{Cstring}) :: Cint
    f = unsafe_pointer_to_objref(fptr)
    interp = TclInterp(iptr)
    args = [unsafe_string(unsafe_load(argv, i)) for i in 1:argc]
    try
        return __setcommandresult(interp, f(args...))
    catch ex
        #println("error during Tk callback: ")
        #Base.display_error(ex, catch_backtrace())
        setresult(interp, "(callback error) " * geterrmsg(ex))
        return TCL_ERROR
    end
end

# With precompilation, `__init__()` carries on initializations that must occur
# at runtime like `cfunction` which returns a raw pointer.
function __init__()
    __initialinterpreter[] = TclInterp(true)
    __currentinterpreter[] = __initialinterpreter[]
    __releaseobject_ref[] = cfunction(__releaseobject, Void, (Ptr{Void},))
    __evalcommand_ref[] = cfunction(__evalcommand, Cint,
                                    (Ptr{Void}, Ptr{Void}, Cint, Ptr{Cstring}))
    __init_types()
    __nothing[] = TclObj{Void}(__newobj(""))
end

# If the function provides a return code, we do want to return it to the
# interpreter, otherwise TCL_OK is assumed.
__setcommandresult(interp::TclInterp, result::Tuple{Cint,Any}) =
    __setcommandresult(interp, result[1], result[2])

__setcommandresult(interp::TclInterp, result) =
    __setcommandresult(interp, TCL_OK, result)

function __setcommandresult(interp::TclInterp, code::Cint, result)
    __setresult(interp, __objptr(result))
    return code
end

"""
```julia
Tcl.createcommand([interp,] [name,] f) -> name
```

creates a command named `name` in Tcl interpreter `interp` (or in the initial
Tcl interpreter if this argument is omitted).  If `name` is missing
`Tcl.autoname("jl_callback")` is used to automatically define a name.  The
command name is returned as a string.  The Tcl command will call the Julia
function `f` as follows:

```julia
f(name, arg1, arg2, ...)
```

where all arguments are strings and the first one is the name of the command.

If the result of the call is a tuple of `(code, value)` of respective type
`(Cint, String)` then `value` is stored as the interpreter result while `code`
(one of `TCL_OK`, `TCL_ERROR`, `TCL_RETURN`, `TCL_BREAK` or `TCL_CONTINUE`) is
returned to Tcl.

The result can also be a scalar value (string or real) which is stored as the
interpreter result and `TCL_OK` is returned to Tcl.  A result which is
`nothing` is the same as an empty string.

See also: [`Tcl.deletecommand`](@ref), [`Tcl.autoname`](@ref).

"""
createcommand(f::Function) =
    createcommand(getinterp(), f)

createcommand(name::Name, f::Function) =
    createcommand(getinterp(), name, f)

createcommand(interp::TclInterp, f::Function) =
    createcommand(interp, autoname("jl_callback"), f)

createcommand(interp::TclInterp, name::Symbol, f::Function) =
    createcommand(interp, string(name), f)

# FIXME: use object, not string name?
function createcommand(interp::TclInterp, name::String, f::Function)
    # Before creating the command, make sure object is not garbage collected
    # until Tcl deletes its reference.
    preserve(f)
    ptr = ccall((:Tcl_CreateCommand, libtcl), Ptr{Void},
                (TclInterpPtr, Cstring, Ptr{Void}, Ptr{Void}, Ptr{Void}),
                interp.ptr, name, __evalcommand_ref[], pointer_from_objref(f),
                __releaseobject_ref[])
    if ptr == C_NULL
        release(f)
        tclerror(interp)
    end
    return name
end

"""
```julia
Tcl.deletecommand([interp,] name)
```

deletes a command named `name` in Tcl interpreter `interp` (or in the initial
Tcl interpreter if this argument is omitted).

See also: [`Tcl.createcommand`](@ref).

"""
deletecommand(name::StringOrSymbol) =
    deletecommand(getinterp(), name)

function deletecommand(interp::TclInterp, name::StringOrSymbol)
    code = ccall((:Tcl_DeleteCommand, libtcl), Cint,
                 (TclInterpPtr, Cstring), interp.ptr, name)
    if code != TCL_OK
        tclerror(interp)
    end
    return nothing
end
