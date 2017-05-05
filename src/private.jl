# Private routines.

__newobject(value::Bool) =
    ccall((:Tcl_NewBooleanObj, libtcl), Ptr{Void}, (Cint,), value)

__newobject(value::Cint) =
    ccall((:Tcl_NewIntObj, libtcl), Ptr{Void}, (Cint,), value)

__newobject(value::Clong) =
    ccall((:Tcl_NewLongObj, libtcl), Ptr{Void}, (Clong,), value)

__newobject{T<:Integer}(value::T) =
    __newobject(sizeof(T) ≤ sizeof(Cint) ? Cint(value) : Clong(value))

__newobject(value::Union{AbstractFloat,Irrational,Rational}) =
    ccall((:Tcl_NewDoubleObj, libtcl), Ptr{Void}, (Cdouble,), value)

# FIXME: Tcl_NewUnicodeObj?
# __newobject(value::String) =
#     ccall((:Tcl_NewStringObj, libtcl), Ptr{Void}, (Cstring, Cint),
#           value, length(value))
# FIXME: use Tcl_NewListObj for arrays?

__setobjresult(interp::TclInterp, obj::Ptr{Void}) =
    ccall((:Tcl_SetObjResult, libtcl), Void, (Ptr{Void}, Ptr{Void}),
          interp.ptr, obj)

__setresult(interp::TclInterp, result::Real) =
    __setobjresult(interp, __newobject(value))

__setresult(interp::TclInterp, result::String, free::Ptr{Void}=TCL_VOLATILE) =
    ccall((:Tcl_SetResult, libtcl), Void, (Ptr{Void}, Cstring, Ptr{Void}),
          interp.ptr, result, free)

__getresult(interp::TclInterp) =
    ccall((:Tcl_GetStringResult, libtcl), Cstring, (Ptr{Void},), interp.ptr)

__getvar(interp::TclInterp, name::String, flags::Cint=VARFLAGS) =
    ccall((:Tcl_GetVar, libtcl), Cstring, (Ptr{Void}, Cstring, Cint),
          interp.ptr, name, flags)

__setvar(interp::TclInterp, name::String, value::String, flags::Cint=VARFLAGS) =
    ccall((:Tcl_SetVar, libtcl), Cstring, (Ptr{Void}, Cstring, Cstring, Cint),
          interp.ptr, name, value, flags)

__unsetvar(interp::TclInterp, name::String, flags::Cint=VARFLAGS) =
    ccall((:Tcl_UnsetSetVar, libtcl), Cint, (Ptr{Void}, Cstring, Cint),
          interp.ptr, name, flags)

__eval(interp::TclInterp, script::String) =
    ccall((:Tcl_Eval, libtcl), Cint, (Ptr{Void}, Cstring), interp.ptr, script)

__deleteinterp(interp::TclInterp) =
    ccall((:Tcl_DeleteInterp, libtcl), Void, (Ptr{Void},), interp.ptr)

__interpdeleted(interp::TclInterp) =
    ccall((:Tcl_InterpDeleted, libtcl), Cint, (Ptr{Void},), interp.ptr)

__interpactive(interp::TclInterp) =
    ccall((:Tcl_InterpActive, libtcl), Cint, (Ptr{Void},), interp.ptr)

__preserve(ptr::Ptr{Void}) =
    ccall((:Tcl_Preserve, libtcl), Void, (Ptr{Void},), ptr)

__release(ptr::Ptr{Void}) =
    ccall((:Tcl_Release, libtcl), Void, (Ptr{Void},), ptr)

