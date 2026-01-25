#
# calls.jl -
#
# Low level interface to Tcl C library.
#
# The convention is to call the functions of the Tcl C library with raw
# arguments (like pointers).  The only changes are:
#
#  - Tcl status code is returned as a `TclStatus`.
#
#  - Return values passed by reference to a C function are not needed in the
#    Julia interface and are returned as tuple of values.
#
#  - Values representing a length or an index are returned as an `Int` (not a
#    `Cint`);
#
#  - Values representing a boolean (a `Cint` in Tcl, a `Bool` in Julia) are
#    automatically converted using consistent conventions.
#
#  - Indices account for Julia convention (Julia indices start at 1, Tcl
#    indices start at 0).
#

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
    typePtr::Ptr{Cvoid}

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
# that the reference count is decremented when the Julia object is finalized.
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

#------------------------------------------------------------------------------
# REFERENCE COUNTING

@inline Tcl_Preserve(ptr::Ptr{T}) where {T} =
    ccall((:Tcl_Preserve, libtcl), Cvoid, (Ptr{T},), ptr)

@inline Tcl_Release(ptr::Ptr{T}) where {T} =
    ccall((:Tcl_Release, libtcl), Cvoid, (Ptr{T},), ptr)

"""
```julia
Tcl_IncrRefCount(objptr) -> objptr
```

increments the reference count of the object referenced by `objptr` and returns
this address.

"""
@inline function Tcl_IncrRefCount(objptr::TclObjPtr)
    ptr = Ptr{Cint}(objptr)
    unsafe_store!(ptr, unsafe_load(ptr) + one(Cint))
    return objptr
end

"""
```julia
Tcl_DecrRefCount(objptr) -> nothing
```

decrements the reference count of the object referenced by `objptr` and delete
it if the number of references is then smaller or equal 0.

"""
@inline function Tcl_DecrRefCount(objptr::TclObjPtr)
    ptr = Ptr{Cint}(objptr)
    newrefcount = unsafe_load(ptr) - one(Cint)
    if newrefcount ≥ 1
        unsafe_store!(ptr, newrefcount)
    else
        ccall((:TclFreeObj, libtcl), Cvoid, (TclObjPtr,), objptr)
    end
    return nothing
end

"""
```julia
Tcl_GetRefCount(objptr)
```

yields the reference count of the object referenced by `objptr`.

"""
@inline Tcl_GetRefCount(objptr::TclObjPtr) = unsafe_load(Ptr{Cint}(objptr))


"""
```julia
Tcl_IsShared(objptr)
```

yields whether the object referenced by `objptr` is shared; that is, its
reference count is greater than one.

"""
@inline Tcl_IsShared(objptr::TclObjPtr) = Tcl_GetRefCount(objptr) > 1


#------------------------------------------------------------------------------
# OBJECTS

"""
```julia
Tcl_NewBooleanObj(value) -> objptr
Tcl_NewIntObj(    value) -> objptr
Tcl_NewLongObj(   value) -> objptr
Tcl_NewWideIntObj(value) -> objptr
Tcl_NewDoubleObj( value) -> objptr
```

"""
@inline Tcl_NewBooleanObj(value::Bool) =
    ccall((:Tcl_NewBooleanObj, libtcl), TclObjPtr,
          (Cint,), (value ? one(Cint) : zero(Cint)))

for (f, Tj, Tc) in ((:Tcl_NewIntObj,     Integer, Cint),
                    (:Tcl_NewLongObj,    Integer, Clong),
                    (:Tcl_NewWideIntObj, Integer, WideInt),
                    (:Tcl_NewDoubleObj,  Real,    Cdouble))
    tup = (f, libtcl)
    @eval @inline $f(value::$Tj) = ccall($tup, TclObjPtr, ($Tc,), value)
end

@inline Tcl_NewStringObj(str::AbstractString) =
    # Use sizeof() not length() because there may be multi-byte characters
    # and use Ptr{Cchar} not Cstring because there may be embedded nulls.
    ccall((:Tcl_NewStringObj, libtcl), TclObjPtr,
          (Ptr{Cchar}, Cint), str, sizeof(str))

@inline Tcl_NewStringObj(ptr::Ptr{T}, nbytes::Integer) where {T<:Byte} =
    ccall((:Tcl_NewStringObj, libtcl), TclObjPtr, (Ptr{T}, Cint), ptr, nbytes)

@inline Tcl_NewByteArrayObj(arr::DenseArray{T}) where {T<:Byte} =
    Tcl_NewByteArrayObj(pointer(arr), sizeof(arr))

@inline Tcl_NewByteArrayObj(ptr::Ptr{T}, nbytes::Integer) where {T<:Byte} =
    ccall((:Tcl_NewByteArrayObj, libtcl), TclObjPtr,
          (Ptr{T}, Cint), ptr, nbytes)

"""
```julia
Tcl_GetBooleanFromObj(intptr, objptr) -> status::TclStatus, value::Bool
Tcl_GetIntFromObj(    intptr, objptr) -> status::TclStatus, value::Cint
Tcl_GetLongFromObj(   intptr, objptr) -> status::TclStatus, value::Clong
Tcl_GetWideIntFromObj(intptr, objptr) -> status::TclStatus, value::Tcl.WideInt
Tcl_GetDoubleFromObj( intptr, objptr) -> status::TclStatus, value::Cdouble
```

"""
@inline function Tcl_GetBooleanFromObj(intptr::TclInterpPtr, objptr::TclObjPtr)
    valref = Ref{Cint}()
    return (ccall((:Tcl_GetBooleanFromObj, libtcl), TclStatus,
                  (TclInterpPtr, TclObjPtr, Ptr{Cint}),
                  intptr, objptr, valref),
            (valref[] != zero(Cint)))
end

for (f, T) in ((:Tcl_GetIntFromObj,     Cint),
               (:Tcl_GetLongFromObj,    Clong),
               (:Tcl_GetWideIntFromObj, WideInt),
               (:Tcl_GetDoubleFromObj,  Cdouble))
    tup = (f, libtcl)
    @eval @inline function $f(intptr::TclInterpPtr, objptr::TclObjPtr)
        valref = Ref{$T}()
        return (ccall($tup, TclStatus, (TclInterpPtr, TclObjPtr, Ptr{$T}),
                      intptr, objptr, valref),
                valref[])
    end
end

"""
```julia
Tcl_GetStringFromObj(objptr) -> ptr::Ptr{Cchar}, len::Int
```

"""
@inline function Tcl_GetStringFromObj(objptr::TclObjPtr)
    lenref = Ref{Cint}()
    return (ccall((:Tcl_GetStringFromObj, libtcl), Ptr{Cchar},
                  (TclObjPtr, Ptr{Cint}), objptr, lenref),
            convert(Int, lenref[]))
end

@inline Tcl_DuplicateObj(objptr::TclObjPtr) =
    ccall((:Tcl_DuplicateObj, libtcl), TclObjPtr, (TclObjPtr,), objptr)

@inline Tcl_GetObjType(name::StringOrSymbol) =
    ccall((:Tcl_GetObjType, libtcl), TclObjTypePtr, (Cstring,), name)

#------------------------------------------------------------------------------
# INTERPRETERS AND EVALUATION OF SCRIPTS

@inline Tcl_CreateInterp() =
    ccall((:Tcl_CreateInterp, libtcl), Ptr{Cvoid}, ())

@inline Tcl_Init(intptr::TclInterpPtr) =
    ccall((:Tcl_Init, libtcl), TclStatus, (TclInterpPtr,), intptr)

@inline Tcl_InterpDeleted(intptr::TclInterpPtr) =
    (zero(Cint) != ccall((:Tcl_InterpDeleted, libtcl), Cint,
                         (TclInterpPtr,), intptr))

@inline Tcl_InterpActive(intptr::TclInterpPtr) =
    (zero(Cint) != ccall((:Tcl_InterpActive, libtcl), Cint,
                         (TclInterpPtr,), intptr))

@inline Tcl_DeleteInterp(intptr::TclInterpPtr) =
    ccall((:Tcl_DeleteInterp, libtcl), Cvoid, (TclInterpPtr,), intptr)

@inline Tcl_SetObjResult(intptr::TclInterpPtr, objptr::TclObjPtr) =
    ccall((:Tcl_SetObjResult, libtcl), Cvoid, (TclInterpPtr, TclObjPtr),
          intptr, objptr)

@inline function Tcl_SetResult(intptr::TclInterpPtr, strptr::Ptr{Cchar},
                               freeproc::Ptr{Cvoid})
    ccall((:Tcl_SetResult, libtcl), Cvoid,
          (TclInterpPtr, Ptr{Cchar}, Ptr{Cvoid}),
          intptr, strptr, freeproc)
end

@inline Tcl_GetObjResult(intptr::TclInterpPtr) =
    ccall((:Tcl_GetObjResult, libtcl), TclObjPtr, (TclInterpPtr,), intptr)

@inline function Tcl_EvalEx(intptr::TclInterpPtr, script::Ptr{Cchar},
                            nbytes::Integer, flags::Integer)
    return ccall((:Tcl_EvalEx, libtcl), TclStatus,
                 (TclInterpPtr, Ptr{Cchar}, Cint, Cint),
                 intptr, script, nbytes, flags)
end

@inline Tcl_EvalObjEx(intptr::TclInterpPtr, objptr::TclObjPtr, flags::Integer) =
    ccall((:Tcl_EvalObjEx, libtcl), TclStatus,
          (TclInterpPtr, TclObjPtr, Cint),
          intptr, objptr, flags)

@inline function Tcl_EvalObjv(intptr::TclInterpPtr, objc::Integer,
                              objv::Ptr{TclObjPtr}, flags::Integer)
    return ccall((:Tcl_EvalObjv, libtcl), TclStatus,
                 (TclInterpPtr, Cint, Ptr{TclObjPtr}, Cint),
                 intptr, objc, objv, flags)
end

"""
```julia
Tcl_DoOneEvent(flags) -> boolean
```
"""
@inline Tcl_DoOneEvent(flags::Integer) =
    (zero(Cint) != ccall((:Tcl_DoOneEvent, libtcl), Cint, (Cint,), flags))

#------------------------------------------------------------------------------
# COMMANDS

@inline function Tcl_CreateCommand(intptr::TclInterpPtr,
                                   name::StringOrSymbol,
                                   evalproc::Ptr{Cvoid},
                                   data::Ptr{Cvoid},
                                   freeproc::Ptr{Cvoid})
    return ccall((:Tcl_CreateCommand, libtcl), Ptr{Cvoid},
                 (TclInterpPtr, Cstring, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                 intptr, name, evalproc, data, freeproc)
end

@inline function Tcl_CreateObjCommand(intptr::TclInterpPtr,
                                      name::StringOrSymbol,
                                      evalproc::Ptr{Cvoid},
                                      data::Ptr{Cvoid},
                                      freeproc::Ptr{Cvoid})
    return ccall((:Tcl_CreateObjCommand, libtcl), TclCommand,
                 (TclInterpPtr, Cstring, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                 intptr, name, evalproc, data, freeproc)
end

@inline Tcl_DeleteCommand(intptr::TclInterpPtr, name::StringOrSymbol) =
    ccall((:Tcl_DeleteCommand, libtcl), TclStatus,
          (TclInterpPtr, Cstring), intptr, name)

@inline Tcl_DeleteCommandFromToken(intptr::TclInterpPtr, token::TclCommand) =
    ccall((:Tcl_DeleteCommandFromToken, libtcl), TclStatus,
          (TclInterpPtr, TclCommand), intptr, token)

@inline Tcl_GetCommandName(intptr::TclInterpPtr, token::TclCommand) =
    ccall((:Tcl_GetCommandName, libtcl), Cstring,
          (TclInterpPtr, TclCommand), intptr, token)

@inline function Tcl_GetCommandFullName(intptr::TclInterpPtr,
                                        token::TclCommand,
                                        objptr::TclObjPtr)
    return ccall((:Tcl_GetCommandFullName, libtcl), Cvoid,
                 (TclInterpPtr, TclCommand, TclObjPtr),
                 intptr, token, objptr)
end

@inline Tcl_GetCommandFromObj(intptr::TclInterpPtr, objptr::TclObjPtr) =
    ccall((:Tcl_GetCommandFromObj, libtcl), TclCommand,
          (TclInterpPtr, TclObjPtr), intptr, objptr)

#------------------------------------------------------------------------------
# VARIABLES

@inline function Tcl_ObjGetVar2(intptr::TclInterpPtr, name1ptr::TclObjPtr,
                                name2ptr::TclObjPtr, flags::Integer)
    return ccall((:Tcl_ObjGetVar2, libtcl), TclObjPtr,
                 (TclInterpPtr, TclObjPtr, TclObjPtr, Cint),
                 intptr, name1ptr, name2ptr, flags)
end

@inline function Tcl_ObjSetVar2(intptr::TclInterpPtr, name1ptr::TclObjPtr,
                                name2ptr::TclObjPtr, valueptr::TclObjPtr,
                                flags::Integer)
    return ccall((:Tcl_ObjSetVar2, libtcl), TclObjPtr,
                 (TclInterpPtr, TclObjPtr, TclObjPtr, TclObjPtr, Cint),
                 intptr, name1ptr, name2ptr, valueptr, flags)
end

for (Tj, Tc) in ((StringOrSymbol, Cstring),
                 (Ptr{Cchar}, Ptr{Cchar}))
    @eval begin

        @inline function Tcl_UnsetVar(intptr::TclInterpPtr, name::$Tj,
                                      flags::Integer)
            return ccall((:Tcl_UnsetVar, libtcl), TclStatus,
                         (TclInterpPtr, $Tc, Cint), intptr, name, flags)
        end

        @inline function Tcl_UnsetVar2(intptr::TclInterpPtr, name1::$Tj,
                                       name2::$Tj, flags::Integer)
            return ccall((:Tcl_UnsetVar2, libtcl), TclStatus,
                         (TclInterpPtr, $Tc, $Tc, Cint),
                         intptr, name1, name2, flags)
        end

    end
end

#------------------------------------------------------------------------------
# LISTS
#
# Note that applying a list function to any Tcl object has the side effect of
# converting the object to a list.  This may be annoying for non-temporary
# objects.

@inline Tcl_NewListObj(objc::Integer, objv::Ptr{TclObjPtr}) =
    ccall((:Tcl_NewListObj, libtcl), TclObjPtr,
          (Cint, Ptr{TclObjPtr}), objc, objv)

@inline function Tcl_SetListObj(objptr::TclObjPtr, objc::Integer,
                                objv::Ptr{TclObjPtr})
    return ccall((:Tcl_SetListObj, libtcl), Cvoid,
                 (TclObjPtr, Cint, Ptr{TclObjPtr}), objptr, objc, objv)
end

"""
```julia
Tcl_ListObjAppendList(intptr, listptr, objptr) -> status::TclStatus
```

appends each element of the list value referenced by `objptr` to to the end of
the list value referenced by `listptr`.

If `listptr` does not already point to a list value, an attempt will be made to
convert it to one.

If `objptr` is not NULL and does not already point to a list value, an attempt
will be made to convert it to one.

If an error occurs while converting a value to be a list value, an error
message is left as the result of the interpreter referenced by `intptr` unless
it is NULL.

"""
@inline function Tcl_ListObjAppendList(intptr::TclInterpPtr,
                                       listptr::TclObjPtr,
                                       objptr::TclObjPtr)
    return ccall((:Tcl_ListObjAppendList, libtcl), TclStatus,
                 (TclInterpPtr, TclObjPtr, TclObjPtr),
                 intptr, listptr, objptr)
end

"""
```julia
Tcl_ListObjAppendElement(intptr, listptr, objptr) -> status::TclStatus
```

appends the single value referenced by `objptr` to to the end of the list value
referenced by `listptr`.

The object referenced by `listptr` must not be shared (its reference count must
be ≤ 1) otherwise  Tcl will panic (and abort the program).  To avoid aborting,
an error is reported.

If `listptr` does not already point to a list value, an attempt will be made to
convert it to one.

If an error occurs while converting a value to be a list value, an error
message is left as the result of the interpreter referenced by `intptr` unless
it is NULL.

"""
@inline function Tcl_ListObjAppendElement(intptr::TclInterpPtr,
                                          listptr::TclObjPtr,
                                          objptr::TclObjPtr) :: TclStatus
    if Tcl_IsShared(listptr)
        msg = "modifying a shared Tcl list is forbidden"
        if intptr == C_NULL
            warn(msg, once=true)
        else
            Tcl_SetResult(intptr, msg)
        end
        return TCL_ERROR
    end
    return ccall((:Tcl_ListObjAppendElement, libtcl), TclStatus,
                 (TclInterpPtr, TclObjPtr, TclObjPtr),
                 intptr, listptr, objptr)
end

"""
```julia
Tcl_ListObjGetElements(intptr, listptr)
    -> status::TclStatus, objc::Int, objv::Ptr{TclObjPtr}
```

Does not touch the reference count of the list object and of its elements.

"""
@inline function Tcl_ListObjGetElements(intptr::TclInterpPtr,
                                        listptr::TclObjPtr)
    objc = Ref{Cint}()
    objv = Ref{Ptr{TclObjPtr}}()
    return (ccall((:Tcl_ListObjGetElements, libtcl), TclStatus,
                  (TclInterpPtr, TclObjPtr, Ptr{Cint}, Ptr{Ptr{TclObjPtr}}),
                  intptr, listptr, objc, objv),
            objc[], objv[])
end


"""
```julia
Tcl_ListObjLength(intptr, listptr) -> status::TclStatus, length::Int
```
"""
@inline function Tcl_ListObjLength(intptr::TclInterpPtr, listptr::TclObjPtr)
    lenref = Ref{Cint}()
    return (ccall((:Tcl_ListObjLength, libtcl), TclStatus,
                  (TclInterpPtr, TclObjPtr, Ptr{Cint}),
                  intptr, listptr, lenref),
            convert(Int, lenref[]))
end

@inline function Tcl_ListObjIndex(intptr::TclInterpPtr, listptr::TclObjPtr,
                                  index::Integer)
    objptr = Ref{TclObjPtr}()
    return (ccall((:Tcl_ListObjIndex, libtcl), TclStatus,
                  (TclInterpPtr, TclObjPtr, Cint, Ptr{TclObjPtr}),
                  intptr, listptr, index - 1, objptr),
            objptr[])
end

"""
```julia
Tcl_ListObjReplace(intptr, listptr, first, count,
                   objc, objv) -> status::TclStatus
```

`first` can be the length of the list plus one and `count` can be 0 to append
to the end of the list.

`objc = 0` and `objv = NULL` are OK to delete elements.

The object referenced by `listptr` must not be shared (its reference count must
be ≤ 1) otherwise  Tcl will panic (and abort the program).  To avoid aborting,
an error is reported.

If `listptr` does not already point to a list value, an attempt will be made to
convert it to one.

"""
@inline function Tcl_ListObjReplace(intptr::TclInterpPtr, listptr::TclObjPtr,
                                    first::Integer, count::Integer,
                                    objc::Integer, objv::Ptr{TclObjPtr})
    if Tcl_IsShared(listptr)
        msg = "modifying a shared Tcl list is forbidden"
        if intptr == C_NULL
            warn(msg, once=true)
        else
            Tcl_SetResult(intptr, msg)
        end
        return TCL_ERROR
    end
    return ccall((:Tcl_ListObjReplace, libtcl), TclStatus,
                 (TclInterpPtr, TclObjPtr, Cint, Cint, Cint, Ptr{TclObjPtr}),
                 intptr, listptr, first + 1, count, objc, objv)
end
