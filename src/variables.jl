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
Tcl.getvar([T=Any,][interp,] name1 [,name2])
```

yields the value of the global variable `name1` or `name1(name2)` in Tcl
interpreter `interp` or in the initial interpreter if this argument is omitted.

Optional argument `T` (`Any` by default) can be used to specify the type of the
returned value.  Some possibilities are:

* If `T` is `Any`, the type of the returned value is determined so as to best
  reflect that of the Tcl variable.

* If `T` is `TclObj`, a managed Tcl object is returned.  This is the most
  efficient if the returned value is intended to be put in a Tcl list or to be
  an argument of a Tcl script or command.

* If `T` is `Bool`, a boolean value is returned.

* If `T` is `String`, a string is returned.

* If `T` is `Char`, a single character is returned (an exception is thrown if
  Tcl object is not a single character string).

* If `T <: Integer`, an integer value of type `T` is returned.

* If `T <: AbstractFloat`, a floating-point value of type `T` is returned.

* If `T` is `Vector`, a vector of values is returned (the Tcl object is
  converted into a list if necessary).

* `TclObj` to get a managed Tcl object;

* If `T` is `Vector`, a vector of values is returned (the Tcl object is
  converted into a list if necessary).

Note that, except if `T` is `Any` or `TclObj`, a conversion of the Tcl
object stored by the variable may be needed.


See also: [`Tcl.exists`](@ref), [`Tcl.setvar`](@ref), [`Tcl.unsetvar`](@ref).

"""
getvar(args...) = getvar(getinterp(), args...)

getvar(::Type{T}, args...) where {T} = getvar(T, getinterp(), args...)

getvar(interp::TclInterp, args...) = getvar(Any, interp, args...)

function getvar(::Type{T}, interp::TclInterp, name::Name) where {T}
    ptr = __getvar(interp, name, VARIABLE_FLAGS)
    ptr != C_NULL || Tcl.error(interp)
    return __objptr_to(T, ptr)
end

function getvar(::Type{T}, interp::TclInterp,
                name1::Name, name2::Name) where {T}
    ptr = __getvar(interp, name1, name2, VARIABLE_FLAGS)
    ptr != C_NULL || Tcl.error(interp)
    return __objptr_to(T, ptr)
end


# Tcl_GetVar would yield an incorrect result if the variable value has embedded
# nulls and symbol Tcl_ObjGetVar2Ex does not exist in the library (despite what
# says the doc.).  Hence we always use Tcl_ObjGetVar2 which may require to
# temporarily convert the variable name into a string object.  There is no loss
# of performances as it turns out that Tcl_GetVar, Tcl_GetVar2 and
# Tcl_ObjGetVar2Ex all call Tcl_ObjGetVar2.
#
# Tcl_ObjGetVar2 does not manage the reference count of the variable name
# parts.
#
# Since all arguments are passed as pointers to Tcl object, we have to take
# care of correctly unreference temporary objects.  Since there can be no
# failure for argument types allowed for variable name parts, we can avoid the
# overhead of the `try ... catch ... finally` statements.

function __getvar(interp::TclInterp, name::Name, flags::Integer)
    nameptr = Tcl_IncrRefCount(__objptr(name))
    objptr = Tcl_ObjGetVar2(interp.ptr, nameptr, C_NULL, flags)
    Tcl_DecrRefCount(nameptr)
    return objptr
end

function __getvar(interp::TclInterp, name1::Name, name2::Name, flags::Integer)
    name1ptr = Tcl_IncrRefCount(__objptr(name1))
    name2ptr = Tcl_IncrRefCount(__objptr(name2))
    objptr = Tcl_ObjGetVar2(interp.ptr, name1ptr, name2ptr, flags)
    Tcl_DecrRefCount(name1ptr)
    Tcl_DecrRefCount(name2ptr)
    return objptr
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
    if __setvar(interp, name, value, VARIABLE_FLAGS) == C_NULL
        Tcl.error(interp)
    end
    return nothing
end

function setvar(interp::TclInterp, name1::Name, name2::Name, value)
    if __setvar(interp, name1, name2, value, VARIABLE_FLAGS) == C_NULL
        Tcl.error(interp)
    end
    return nothing
end

# Like Tcl_ObjGetVar2Ex, Tcl_ObjSetVar2Ex may be not found in library so we
# avoid using it.  In fact, it turns out that Tcl_SetVar, Tcl_SetVar2 and
# Tcl_ObjSetVar2Ex call Tcl_ObjGetVar2 to do their stuff, so we only use
# Tcl_ObjGetVar2 with no loss of performances as it turns out that Tcl_SetVar
# calls Tcl_ObjGetVar2.
#
# Tcl_ObjSetVar2 does not manage the reference count of the variable name
# parts but do manage the reference count of the variable value.
#
# Same remarks as for `__getvar` about correctly unreferencing temporary
# objects and avoiding `try ... catch` statements.

function __setvar(interp::TclInterp, name::Name, value, flags::Integer)
    valueptr = Tcl_IncrRefCount(__objptr(value)) # must be first
    nameptr = Tcl_IncrRefCount(__objptr(name))
    objptr = Tcl_ObjSetVar2(interp.ptr, nameptr, C_NULL, valueptr, flags)
    Tcl_DecrRefCount(valueptr)
    Tcl_DecrRefCount(nameptr)
    return objptr
end

function __setvar(interp::TclInterp, name1::Name, name2::Name,
                  value, flags::Integer)
    valueptr = Tcl_IncrRefCount(__objptr(value)) # must be first
    name1ptr = Tcl_IncrRefCount(__objptr(name1))
    name2ptr = Tcl_IncrRefCount(__objptr(name2))
    objptr = Tcl_ObjSetVar2(interp.ptr, name1ptr, name2ptr, valueptr, flags)
    Tcl_DecrRefCount(valueptr)
    Tcl_DecrRefCount(name1ptr)
    Tcl_DecrRefCount(name2ptr)
    return objptr
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
    status = __unsetvar(interp, __string(name), flags)
    if status != TCL_OK && ! nocomplain
        Tcl.error(interp)
    end
    return nothing
end

function unsetvar(interp::TclInterp, name1::Name, name2::Name;
                  nocomplain::Bool=false)
    flags = (nocomplain ? TCL_GLOBAL_ONLY : (TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG))
    status = __unsetvar(interp, __string(name1), __string(name2), flags)
    if status != TCL_OK && ! nocomplain
        Tcl.error(interp)
    end
    return nothing
end

# `TclUnsetVarObj2` would be the function to call here but, unfortunately, only
# `Tcl_UnsetVar` and `Tcl_UnsetVar2` are available which both require strings
# for the variable name parts.

function __unsetvar(interp::TclInterp, name::String, flags::Integer)
    if (ptr = __cstring(name)[1]) != C_NULL
        status = Tcl_UnsetVar(interp.ptr, ptr, flags)
    else
        status = Tcl.eval(TclStatus, interp, "unset {$name}")
    end
    return status
end

function __unsetvar(interp::TclInterp, name1::String, name2::String,
                    flags::Integer)
    if ((ptr1 = __cstring(name1)[1]) != C_NULL &&
        (ptr2 = __cstring(name2)[1]) != C_NULL)
        status = Tcl_UnsetVar2(interp.ptr, ptr1, ptr2, flags)
    else
        status = Tcl.eval(TclStatus, "unset {$name1($name2)}")
    end
    return status
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
    return (__getvar(interp, name, TCL_GLOBAL_ONLY) != C_NULL)
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

__cstring(sym::Symbol) = __cstring(string(sym))
