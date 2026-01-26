"""

Glue code to Tcl C library.

The convention is to call the functions of the Tcl C library with raw arguments (like
pointers). The only changes are:

 - Tcl status code is returned as a `TclStatus`.

 - Return values passed by reference to a C function are not needed in the Julia interface
   and are returned as tuple of values.

 - Values representing a length or an index are returned as an `Int` (not a `Cint`);

 - Values representing a boolean (a `Cint` in Tcl, a `Bool` in Julia) are automatically
   converted using consistent conventions.

 - Indices account for Julia convention (Julia indices start at 1, Tcl indices start at 0).

"""
module Glue

using Tcl_jll
using Tk_jll
using CEnum

"""
    TclStatus

Type of result returned by evaluating Tcl scripts or commands. Possible values are:

* `TCL_OK`: Command completed normally; the interpreter's result contains the command's
  result.

* `TCL_ERROR`: The command couldn't be completed successfully; the interpreter's result
  describes what went wrong.

* `TCL_RETURN`: The command requests that the current function return; the interpreter's
  result contains the function's return value.

* `TCL_BREAK`: The command requests that the innermost loop be exited; the interpreter's
  result is meaningless.

* `TCL_CONTINUE`: Go on to the next iteration of the current loop; the interpreter's result
  is meaningless.

"""
@cenum TclStatus::Cint begin
    TCL_OK       = 0
    TCL_ERROR    = 1
    TCL_RETURN   = 2
    TCL_BREAK    = 3
    TCL_CONTINUE = 4
end

# Flags for settings the result.
const TCL_VOLATILE = Ptr{Cvoid}(1)
const TCL_STATIC   = Ptr{Cvoid}(0)
const TCL_DYNAMIC  = Ptr{Cvoid}(3)

# Flags for Tcl variables.
const TCL_GLOBAL_ONLY    = Cint(1)
const TCL_NAMESPACE_ONLY = Cint(2)
const TCL_APPEND_VALUE   = Cint(4)
const TCL_LIST_ELEMENT   = Cint(8)
const TCL_LEAVE_ERR_MSG  = Cint(0x200)

# Flags for Tcl processing events.  Set TCL_DONT_WAIT to not sleep: process
# only events that are ready at the time of the call.  Set TCL_ALL_EVENTS to
# process all kinds of events: equivalent to OR-ing together all of the below
# flags or specifying none of them.
const TCL_DONT_WAIT     = Cint(1<<1)
const TCL_WINDOW_EVENTS = Cint(1<<2) # Process window system events.
const TCL_FILE_EVENTS   = Cint(1<<3) # Process file events.
const TCL_TIMER_EVENTS  = Cint(1<<4) # Process timer events.
const TCL_IDLE_EVENTS   = Cint(1<<5) # Process idle callbacks.
const TCL_ALL_EVENTS    = ~TCL_DONT_WAIT      # Process all kinds of events.

# The following values control how blocks are combined into photo images when
# the alpha component of a pixel is not 255, a.k.a. the compositing rule.
const TK_PHOTO_COMPOSITE_OVERLAY = Cint(0)
const TK_PHOTO_COMPOSITE_SET     = Cint(1)

# Flags for evaluating scripts/commands.
const TCL_NO_EVAL       = Cint(0x010000)
const TCL_EVAL_GLOBAL   = Cint(0x020000)
const TCL_EVAL_DIRECT   = Cint(0x040000)
const TCL_EVAL_INVOKE   = Cint(0x080000)
const TCL_CANCEL_UNWIND = Cint(0x100000)
const TCL_EVAL_NOERR    = Cint(0x200000)

# Tcl wide integer is 64-bit integer.
const Tcl_WideInt = Int64

# Client data used by commands and callbacks.
const ClientData = Ptr{Cvoid}

# Opaque structures.
abstract type Tcl_ObjType end
abstract type Tcl_Obj end
abstract type Tcl_Interp end
abstract type Tcl_Command_ end

# Token used by Tcl to identify an object command.
const Tcl_Command = Ptr{Tcl_Command_}

#------------------------------------------------------------- Inference and introspection -

# Return the least multiple of `b` that is greater or equal `a`. `a` and `b` must be
# non-negative.
roundup(a::Integer, b::Integer) = roundup(promote(a, b)...)
roundup(a::T, b::T) where {T<:Integer} = div(b - one(T) + a, b)*b

# Return the alignment in a C structure of an object of type `T`.
alignment(::Type{T}) where {T} = fieldoffset(Tuple{UInt8,T}, 2)

#----------------------------------------------------------------------- Tcl_Obj structure -

"""
    FakeObj{T,N}

Julia equivalent type of C structure `Tcl_Obj` assuming member `internalRep` is of type `T`
and preceded by a padding of `N` bytes. This is used to compute the types and offsets of the
fields of a `Tcl_Obj` and the full size of a `Tcl_Obj`.

The definition of `Tcl_obj` in `<tcl.h>` is:

```c
typedef struct Tcl_ObjType Tcl_ObjType;
typedef struct Tcl_Obj {
    int refCount;
    char *bytes;
    int length;
    const Tcl_ObjType *typePtr;
    union {
        long longValue;
        double doubleValue;
        void *otherValuePtr;
        Tcl_WideInt wideValue;
        struct {
            void *ptr1;
            void *ptr2;
        } twoPtrValue;
        struct {
            void *ptr;
            unsigned long value;
        } ptrAndLongRep;
    } internalRep;
} Tcl_Obj;
```

"""
struct FakeObj{T,N}
    refCount::Cint
    bytes::Ptr{Cchar}
    length::Cint
    typePtr::Ptr{Tcl_ObjType}
    padding::NTuple{N,UInt8}
    internalRep::T
end

# Tuple of possible types in `internalRep` union.
const Tcl_Obj_internalRep_types = (Clong, Cdouble, Ptr{Cvoid}, Tcl_WideInt,
                                   Tuple{Ptr{Cvoid}, Ptr{Cvoid}},
                                   Tuple{Ptr{Cvoid}, Culong})

# Define constants for the types and offsets of all fields but the last ones.
for (index, name) in enumerate(fieldnames(FakeObj{Nothing,0}))
    name == :padding && break
    @eval begin
        const $(Symbol("Tcl_Obj_",name,"_type")) = $(fieldtype(FakeObj{Nothing,0}, index))
        const $(Symbol("Tcl_Obj_",name,"_offset")) = $(fieldoffset(FakeObj{Nothing,0}, index))
    end
end

# Alignment of `internalRep` union is the maximal alignment of the different possible types.
const Tcl_Obj_internalRep_align = maximum(map(alignment, Tcl_Obj_internalRep_types))
const Tcl_Obj_internalRep_offset = roundup(sizeof(FakeObj{Nothing,0}), Tcl_Obj_internalRep_align)
const Tcl_Obj_internalRep_pad = Tcl_Obj_internalRep_offset - sizeof(FakeObj{Nothing,0})

# NOTE The number of padding bytes `N` must be an `Int` otherwise the result is wrong.
const Tcl_Obj_size = maximum(map(T -> sizeof(FakeObj{T,Int(Tcl_Obj_internalRep_pad)}),
                                 Tcl_Obj_internalRep_types))

# NOTE Some initialization are needed before calling `TclFreeObj`. This may be done by
#      creating an interpreter.
function TclFreeObj(obj)
    @ccall libtcl.TclFreeObj(ptr::Ptr{Tcl_Obj})::Cvoid
end

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

@static if Tcl_Obj_refCount_offset != 0
    error("it is assumed that refCount comes first in Tcl_Obj structure")
end

#------------------------------------------------------------------------------
# REFERENCE COUNTING

function Tcl_Preserve(data)
    @ccall libtcl.Tcl_Preserve(data::ClientData)::Cvoid
end

function Tcl_Release(data)
    @ccall libtcl.Tcl_Release(data::ClientData)::Cvoid
end

"""
```julia
Tcl_IncrRefCount(objptr) -> objptr
```

increments the reference count of the object referenced by `objptr` and returns
this address.

"""
@inline function Tcl_IncrRefCount(objptr::Ptr{Tcl_Obj})
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
@inline function Tcl_DecrRefCount(objptr::Ptr{Tcl_Obj})
    ptr = Ptr{Cint}(objptr)
    newrefcount = unsafe_load(ptr) - one(Cint)
    if newrefcount ≥ 1
        unsafe_store!(ptr, newrefcount)
    else
        ccall((:TclFreeObj, libtcl), Cvoid, (Ptr{Tcl_Obj},), objptr)
    end
    return nothing
end

"""
```julia
Tcl_GetRefCount(objptr)
```

yields the reference count of the object referenced by `objptr`.

"""
@inline Tcl_GetRefCount(objptr::Ptr{Tcl_Obj}) = unsafe_load(Ptr{Cint}(objptr))


"""
```julia
Tcl_IsShared(objptr)
```

yields whether the object referenced by `objptr` is shared; that is, its
reference count is greater than one.

"""
@inline Tcl_IsShared(objptr::Ptr{Tcl_Obj}) = Tcl_GetRefCount(objptr) > 1


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
    ccall((:Tcl_NewBooleanObj, libtcl), Ptr{Tcl_Obj},
          (Cint,), (value ? one(Cint) : zero(Cint)))

for (f, Tj, Tc) in ((:Tcl_NewIntObj,     Integer, Cint),
                    (:Tcl_NewLongObj,    Integer, Clong),
                    (:Tcl_NewWideIntObj, Integer, Tcl_WideInt),
                    (:Tcl_NewDoubleObj,  Real,    Cdouble))
    tup = (f, libtcl)
    @eval @inline $f(value::$Tj) = ccall($tup, Ptr{Tcl_Obj}, ($Tc,), value)
end

@inline Tcl_NewStringObj(str::AbstractString) =
    # Use sizeof() not length() because there may be multi-byte characters
    # and use Ptr{Cchar} not Cstring because there may be embedded nulls.
    ccall((:Tcl_NewStringObj, libtcl), Ptr{Tcl_Obj},
          (Ptr{Cchar}, Cint), str, sizeof(str))

@inline Tcl_NewStringObj(ptr::Ptr{T}, nbytes::Integer) where {T<:UInt8} =
    ccall((:Tcl_NewStringObj, libtcl), Ptr{Tcl_Obj}, (Ptr{T}, Cint), ptr, nbytes)

@inline Tcl_NewByteArrayObj(arr::DenseArray{T}) where {T<:UInt8} =
    Tcl_NewByteArrayObj(pointer(arr), sizeof(arr))

@inline Tcl_NewByteArrayObj(ptr::Ptr{T}, nbytes::Integer) where {T<:UInt8} =
    ccall((:Tcl_NewByteArrayObj, libtcl), Ptr{Tcl_Obj},
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
@inline function Tcl_GetBooleanFromObj(intptr::Ptr{Tcl_Interp}, objptr::Ptr{Tcl_Obj})
    valref = Ref{Cint}()
    return (ccall((:Tcl_GetBooleanFromObj, libtcl), TclStatus,
                  (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Ptr{Cint}),
                  intptr, objptr, valref),
            (valref[] != zero(Cint)))
end

for (f, T) in ((:Tcl_GetIntFromObj,     Cint),
               (:Tcl_GetLongFromObj,    Clong),
               (:Tcl_GetWideIntFromObj, Tcl_WideInt),
               (:Tcl_GetDoubleFromObj,  Cdouble))
    tup = (f, libtcl)
    @eval @inline function $f(intptr::Ptr{Tcl_Interp}, objptr::Ptr{Tcl_Obj})
        valref = Ref{$T}()
        return (ccall($tup, TclStatus, (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Ptr{$T}),
                      intptr, objptr, valref),
                valref[])
    end
end

"""
```julia
Tcl_GetStringFromObj(objptr) -> ptr::Ptr{Cchar}, len::Int
```

"""
@inline function Tcl_GetStringFromObj(objptr::Ptr{Tcl_Obj})
    lenref = Ref{Cint}()
    return (ccall((:Tcl_GetStringFromObj, libtcl), Ptr{Cchar},
                  (Ptr{Tcl_Obj}, Ptr{Cint}), objptr, lenref),
            convert(Int, lenref[]))
end

@inline Tcl_DuplicateObj(objptr::Ptr{Tcl_Obj}) =
    ccall((:Tcl_DuplicateObj, libtcl), Ptr{Tcl_Obj}, (Ptr{Tcl_Obj},), objptr)

@inline Tcl_GetObjType(name) =
    ccall((:Tcl_GetObjType, libtcl), Ptr{Tcl_ObjType}, (Cstring,), name)

#------------------------------------------------------------------------------
# INTERPRETERS AND EVALUATION OF SCRIPTS

@inline Tcl_CreateInterp() =
    ccall((:Tcl_CreateInterp, libtcl), Ptr{Cvoid}, ())

@inline Tcl_Init(intptr::Ptr{Tcl_Interp}) =
    ccall((:Tcl_Init, libtcl), TclStatus, (Ptr{Tcl_Interp},), intptr)

@inline Tcl_InterpDeleted(intptr::Ptr{Tcl_Interp}) =
    (zero(Cint) != ccall((:Tcl_InterpDeleted, libtcl), Cint,
                         (Ptr{Tcl_Interp},), intptr))

@inline Tcl_InterpActive(intptr::Ptr{Tcl_Interp}) =
    (zero(Cint) != ccall((:Tcl_InterpActive, libtcl), Cint,
                         (Ptr{Tcl_Interp},), intptr))

@inline Tcl_DeleteInterp(intptr::Ptr{Tcl_Interp}) =
    ccall((:Tcl_DeleteInterp, libtcl), Cvoid, (Ptr{Tcl_Interp},), intptr)

@inline Tcl_SetObjResult(intptr::Ptr{Tcl_Interp}, objptr::Ptr{Tcl_Obj}) =
    ccall((:Tcl_SetObjResult, libtcl), Cvoid, (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}),
          intptr, objptr)

@inline function Tcl_SetResult(intptr::Ptr{Tcl_Interp}, strptr::Ptr{Cchar},
                               freeproc::Ptr{Cvoid})
    ccall((:Tcl_SetResult, libtcl), Cvoid,
          (Ptr{Tcl_Interp}, Ptr{Cchar}, Ptr{Cvoid}),
          intptr, strptr, freeproc)
end

@inline Tcl_GetObjResult(intptr::Ptr{Tcl_Interp}) =
    ccall((:Tcl_GetObjResult, libtcl), Ptr{Tcl_Obj}, (Ptr{Tcl_Interp},), intptr)

@inline function Tcl_EvalEx(intptr::Ptr{Tcl_Interp}, script::Ptr{Cchar},
                            nbytes::Integer, flags::Integer)
    return ccall((:Tcl_EvalEx, libtcl), TclStatus,
                 (Ptr{Tcl_Interp}, Ptr{Cchar}, Cint, Cint),
                 intptr, script, nbytes, flags)
end

@inline Tcl_EvalObjEx(intptr::Ptr{Tcl_Interp}, objptr::Ptr{Tcl_Obj}, flags::Integer) =
    ccall((:Tcl_EvalObjEx, libtcl), TclStatus,
          (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Cint),
          intptr, objptr, flags)

@inline function Tcl_EvalObjv(intptr::Ptr{Tcl_Interp}, objc::Integer,
                              objv::Ptr{Ptr{Tcl_Obj}}, flags::Integer)
    return ccall((:Tcl_EvalObjv, libtcl), TclStatus,
                 (Ptr{Tcl_Interp}, Cint, Ptr{Ptr{Tcl_Obj}}, Cint),
                 intptr, objc, objv, flags)
end

function Tcl_DoOneEvent(flags)
    @ccall libtcl.Tcl_DoOneEvent(flags::Cint)::Cint
end

function Tcl_DoWhenIdle(proc, clientData)
    @ccall libtcl.Tcl_DoWhenIdle(proc::Ptr{Tcl_IdleProc}, clientData::ClientData)::Cvoid
end

#------------------------------------------------------------------------------
# COMMANDS

@inline function Tcl_CreateCommand(intptr::Ptr{Tcl_Interp},
                                   name,
                                   evalproc::Ptr{Cvoid},
                                   data::Ptr{Cvoid},
                                   freeproc::Ptr{Cvoid})
    return ccall((:Tcl_CreateCommand, libtcl), Ptr{Cvoid},
                 (Ptr{Tcl_Interp}, Cstring, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                 intptr, name, evalproc, data, freeproc)
end

@inline function Tcl_CreateObjCommand(intptr::Ptr{Tcl_Interp},
                                      name,
                                      evalproc::Ptr{Cvoid},
                                      data::Ptr{Cvoid},
                                      freeproc::Ptr{Cvoid})
    return ccall((:Tcl_CreateObjCommand, libtcl), Tcl_Command,
                 (Ptr{Tcl_Interp}, Cstring, Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}),
                 intptr, name, evalproc, data, freeproc)
end

@inline Tcl_DeleteCommand(intptr::Ptr{Tcl_Interp}, name) =
    ccall((:Tcl_DeleteCommand, libtcl), TclStatus,
          (Ptr{Tcl_Interp}, Cstring), intptr, name)

@inline Tcl_DeleteCommandFromToken(intptr::Ptr{Tcl_Interp}, token::Tcl_Command) =
    ccall((:Tcl_DeleteCommandFromToken, libtcl), TclStatus,
          (Ptr{Tcl_Interp}, Tcl_Command), intptr, token)

@inline Tcl_GetCommandName(intptr::Ptr{Tcl_Interp}, token::Tcl_Command) =
    ccall((:Tcl_GetCommandName, libtcl), Cstring,
          (Ptr{Tcl_Interp}, Tcl_Command), intptr, token)

@inline function Tcl_GetCommandFullName(intptr::Ptr{Tcl_Interp},
                                        token::Tcl_Command,
                                        objptr::Ptr{Tcl_Obj})
    return ccall((:Tcl_GetCommandFullName, libtcl), Cvoid,
                 (Ptr{Tcl_Interp}, Tcl_Command, Ptr{Tcl_Obj}),
                 intptr, token, objptr)
end

@inline Tcl_GetCommandFromObj(intptr::Ptr{Tcl_Interp}, objptr::Ptr{Tcl_Obj}) =
    ccall((:Tcl_GetCommandFromObj, libtcl), Tcl_Command,
          (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}), intptr, objptr)

#------------------------------------------------------------------------------
# VARIABLES

@inline function Tcl_ObjGetVar2(intptr::Ptr{Tcl_Interp}, name1ptr::Ptr{Tcl_Obj},
                                name2ptr::Ptr{Tcl_Obj}, flags::Integer)
    return ccall((:Tcl_ObjGetVar2, libtcl), Ptr{Tcl_Obj},
                 (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Ptr{Tcl_Obj}, Cint),
                 intptr, name1ptr, name2ptr, flags)
end

@inline function Tcl_ObjSetVar2(intptr::Ptr{Tcl_Interp}, name1ptr::Ptr{Tcl_Obj},
                                name2ptr::Ptr{Tcl_Obj}, valueptr::Ptr{Tcl_Obj},
                                flags::Integer)
    return ccall((:Tcl_ObjSetVar2, libtcl), Ptr{Tcl_Obj},
                 (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Ptr{Tcl_Obj}, Ptr{Tcl_Obj}, Cint),
                 intptr, name1ptr, name2ptr, valueptr, flags)
end

function Tcl_UnsetVar(interp, name, flags)
    return ccall((:Tcl_UnsetVar, libtcl), TclStatus,
                 (Ptr{Tcl_Interp}, Cstring, Cint), interp, name, flags)
end

function Tcl_UnsetVar2(interp, name1, name2, flags)
    return ccall((:Tcl_UnsetVar2, libtcl), TclStatus,
                 (Ptr{Tcl_Interp}, Cstring, Cstring, Cint),
                 interp, name1, name2, flags)
end

#------------------------------------------------------------------------------
# LISTS
#
# Note that applying a list function to any Tcl object has the side effect of
# converting the object to a list.  This may be annoying for non-temporary
# objects.

@inline Tcl_NewListObj(objc::Integer, objv::Ptr{Ptr{Tcl_Obj}}) =
    ccall((:Tcl_NewListObj, libtcl), Ptr{Tcl_Obj},
          (Cint, Ptr{Ptr{Tcl_Obj}}), objc, objv)

@inline function Tcl_SetListObj(objptr::Ptr{Tcl_Obj}, objc::Integer,
                                objv::Ptr{Ptr{Tcl_Obj}})
    return ccall((:Tcl_SetListObj, libtcl), Cvoid,
                 (Ptr{Tcl_Obj}, Cint, Ptr{Ptr{Tcl_Obj}}), objptr, objc, objv)
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
@inline function Tcl_ListObjAppendList(intptr::Ptr{Tcl_Interp},
                                       listptr::Ptr{Tcl_Obj},
                                       objptr::Ptr{Tcl_Obj})
    return ccall((:Tcl_ListObjAppendList, libtcl), TclStatus,
                 (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Ptr{Tcl_Obj}),
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
@inline function Tcl_ListObjAppendElement(intptr::Ptr{Tcl_Interp},
                                          listptr::Ptr{Tcl_Obj},
                                          objptr::Ptr{Tcl_Obj}) :: TclStatus
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
                 (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Ptr{Tcl_Obj}),
                 intptr, listptr, objptr)
end

"""
```julia
Tcl_ListObjGetElements(intptr, listptr)
    -> status::TclStatus, objc::Int, objv::Ptr{Ptr{Tcl_Obj}}
```

Does not touch the reference count of the list object and of its elements.

"""
@inline function Tcl_ListObjGetElements(intptr::Ptr{Tcl_Interp},
                                        listptr::Ptr{Tcl_Obj})
    objc = Ref{Cint}()
    objv = Ref{Ptr{Ptr{Tcl_Obj}}}()
    return (ccall((:Tcl_ListObjGetElements, libtcl), TclStatus,
                  (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Ptr{Cint}, Ptr{Ptr{Ptr{Tcl_Obj}}}),
                  intptr, listptr, objc, objv),
            objc[], objv[])
end


"""
```julia
Tcl_ListObjLength(intptr, listptr) -> status::TclStatus, length::Int
```
"""
@inline function Tcl_ListObjLength(intptr::Ptr{Tcl_Interp}, listptr::Ptr{Tcl_Obj})
    lenref = Ref{Cint}()
    return (ccall((:Tcl_ListObjLength, libtcl), TclStatus,
                  (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Ptr{Cint}),
                  intptr, listptr, lenref),
            convert(Int, lenref[]))
end

@inline function Tcl_ListObjIndex(intptr::Ptr{Tcl_Interp}, listptr::Ptr{Tcl_Obj},
                                  index::Integer)
    objptr = Ref{Ptr{Tcl_Obj}}()
    return (ccall((:Tcl_ListObjIndex, libtcl), TclStatus,
                  (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Cint, Ptr{Ptr{Tcl_Obj}}),
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
@inline function Tcl_ListObjReplace(intptr::Ptr{Tcl_Interp}, listptr::Ptr{Tcl_Obj},
                                    first::Integer, count::Integer,
                                    objc::Integer, objv::Ptr{Ptr{Tcl_Obj}})
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
                 (Ptr{Tcl_Interp}, Ptr{Tcl_Obj}, Cint, Cint, Cint, Ptr{Ptr{Tcl_Obj}}),
                 intptr, listptr, first + 1, count, objc, objv)
end

end # module
