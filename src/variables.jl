#
# variables.jl -
#
# Julia interface to Tcl variables.
#

# Manage to make any Tcl interpreter usable as an indexable collection with
# respect to its global variables.

Base.getindex(interp::TclInterp, name) = getvar(interp, name)
Base.getindex(interp::TclInterp, name1, name2) = getvar(interp, name1, name2)

Base.setindex!(interp::TclInterp, value, name) = setvar(interp, name, value)
Base.setindex!(interp::TclInterp, value, name1, name2) =
    setvar(interp, name1, name2, value)

Base.setindex!(interp::TclInterp, ::Void, name) =
    unsetvar(interp, name; nocomplain=true)
Base.setindex!(interp::TclInterp, ::Void, name1, name2) =
    unsetvar(interp, name1, name2; nocomplain=true)

Base.haskey(interp::TclInterp, name) = exists(interp, name)
Base.haskey(interp::TclInterp, name1, name2) = exists(interp, name1, name2)


const VARIABLE_FLAGS = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG

"""
```julia
Tcl.getvar([T,][interp,] name1 [,name2])
```

yields the value of the global variable `name1` or `name1(name2)` in Tcl
interpreter `interp` or in the initial interpreter if this argument is omitted.

If optional argument `T` is omitted, the type of the returned value reflects
that of the Tcl variable; otherwise, `T` can be `String` to get the string
representation of the value or `TclObj` to get a managed Tcl object.  The
latter type is more efficient if the returned value is intended to be put in a
Tcl list or to be an argument of a Tcl script or command.

See also: [`Tcl.exists`](@ref), [`Tcl.setvar`](@ref), [`Tcl.unsetvar`](@ref).

"""
getvar(args...) = getvar(getinterp(), args...)

getvar(::Type{T}, args...) where {T} = getvar(T, getinterp(), args...)

function getvar(interp::TclInterp, name::Name)
    ptr = __getvar(interp, name, C_NULL, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __objptr_to_value(ptr)
end

function getvar(::Type{TclObj}, interp::TclInterp, name::Name)
    ptr = __getvar(interp, name, C_NULL, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __objptr_to_object(ptr)
end

function getvar(::Type{String}, interp::TclInterp, name::Name)
    ptr = __getvar(interp, name, C_NULL, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __objptr_to_string(ptr)
end

function getvar(interp::TclInterp, name1::Name, name2::Name)
    ptr = __getvar(interp, name1, name2, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __objptr_to_value(ptr)
end

function getvar(::Type{TclObj}, interp::TclInterp, name1::Name, name2::Name)
    ptr = __getvar(interp, name1, name2, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __objptr_to_object(ptr)
end

function getvar(::Type{String}, interp::TclInterp, name1::Name, name2::Name)
    ptr = __getvar(interp, name1, name2, VARIABLE_FLAGS)
    ptr != C_NULL || tclerror(interp)
    return __objptr_to_string(ptr)
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
