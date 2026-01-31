"""
    Tcl.exists([interp,] name)
    haskey(interp, name)

    Tcl.exists([interp,] part1, part2)
    haskey(interp, (part1, part2))

Return whether global variable `name` or `part1(part2)` is defined in Tcl interpreter
`interp` or in the shared interpreter of the calling thread if this argument is omitted.

# See also

[`Tcl.getvar`](@ref), [`Tcl.setvar`](@ref), and [`Tcl.unsetvar`](@ref).

"""
function exists end

for (name, decl) in ((:name,)         => (:(name::Name),),
                     (:part1, :part2) => (:(part1::Name), :(part2::Name)))
    @eval begin
        function exists($(decl...))
            return exists(TclInterp(), $(name...))
        end

        function exists(interp::TclInterp, $(decl...))
            GC.@preserve interp $(name...) begin
                return !isnull(unsafe_getvar(interp, $(name...), TCL_GLOBAL_ONLY))
            end
        end

        # Manage to make any Tcl interpreter usable as an indexable collection with respect to its
        # global variables.
        function Base.haskey(interp::TclInterp, $(decl...))
            return exists(interp, $(name...))
        end

        function Base.getindex(interp::TclInterp, $(decl...))
            return getvar(interp, $(name...))
        end
        function Base.setindex!(interp::TclInterp, value, $(decl...))
            setvar(Nothing, interp, $(name...), value)
            return interp
        end

        # TODO Replace `nothing` by `unset` of the `UnsetIndex` package.
        function Base.setindex!(interp::TclInterp, ::Nothing, $(decl...))
            unsetvar(interp, $(name...); nocomplain=true)
            return interp
        end
    end
end

"""
    Tcl.getvar([T=TclObj,][interp,] part1[, part2])

Return the value of the global variable `part1` or `part1(part2)` in Tcl interpreter
`interp` or in the shared interpreter of the calling thread if this argument is omitted.

Optional argument `T` (`Any` by default) can be used to specify the type of the returned
value. Some possibilities are:

* If `T` is `Any`, the type of the returned value is determined so as to best
  reflect that of the Tcl variable.

* If `T` is `TclObj`, a managed Tcl object is returned. This is the most efficient if the
  returned value is intended to be put in a Tcl list or to be an argument of a Tcl script or
  command.

* If `T` is `Bool`, a boolean value is returned.

* If `T` is `String`, a string is returned.

* If `T` is `Char`, a single character is returned (an exception is thrown if Tcl object is
  not a single character string).

* If `T <: Integer`, an integer value of type `T` is returned.

* If `T <: AbstractFloat`, a floating-point value of type `T` is returned.

* If `T` is `Vector`, a vector of values is returned (the Tcl object is converted into a
  list if necessary).

* `TclObj` to get a managed Tcl object;

Note that, except if `T` is `Any` or `TclObj`, a conversion of the Tcl object stored by the
variable may be needed.


See also: [`Tcl.exists`](@ref), [`Tcl.setvar`](@ref), [`Tcl.unsetvar`](@ref).

"""
function getvar end

const getvar_default_flags = (TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG);

for (name, decl) in ((:name,)         => (:(name::Name),),
                     (:part1, :part2) => (:(part1::Name), :(part2::Name)))
    @eval begin
        function getvar($(decl...); kwds...)
            getvar(TclInterp(), $(name...); kwds...)
        end
        function getvar(::Type{T}, $(decl...); kwds...) where {T}
            getvar(T, TclInterp(), $(name...); kwds...)
        end
        function getvar(interp::TclInterp, $(decl...); kwds...)
            getvar(TclObj, interp, $(name...); kwds...)
        end
        function getvar(::Type{T}, interp::TclInterp, $(decl...);
                        flags::Integer = getvar_default_flags) where {T}
            GC.@preserve interp $(name...) begin
                value_ptr = unsafe_getvar(interp, $(name...), flags)
                isnull(value_ptr) && getvar_error(interp, $(name...), flags)
                if T == TclObj
                    return _TclObj(value_ptr)
                else
                    unsafe_incr_refcnt(value_ptr)
                    try
                        # Attempt conversion.
                        return unsafe_get(T, value_ptr)
                    finally
                        unsafe_decr_refcnt(value_ptr)
                    end
                end
            end
        end
        @noinline function getvar_error(interp::TclInterp, $(decl...), flags::Integer)
            local mesg
            if iszero(flags & TCL_LEAVE_ERR_MSG)
                varname = variable_name($(name...))
                mesg = "Tcl variable \"$varname\" does not exist"
            else
                mesg = get(String, interp)
            end
            throw(TclError(mesg))
        end
    end
end

variable_name(name::Name) = string(name)
variable_name(part1::Name, part2::Name) = "$(part1)($(part2))"

"""
    Tcl.setvar([interp,] name, value) -> nothing
    interp[name] = value

    Tcl.setvar([interp,] part1, part2, value) -> nothing
    interp[part1, part2] = value

    Tcl.setvar(T, [interp,] part1, part2, value) -> val::T

Set global variable `name` or `part1(part2)` to be `value` in Tcl interpreter `interp` or in
the shared interpreter of the calling thread if this argument is omitted.

In the last case, the new value of the variable is returned as an instance of type `T` (can
be `TclObj`). The new value may be different from `value` because of trace(s) associated to
this variable.

# See also

[`Tcl.getvar`](@ref), [`Tcl.exists`](@ref), and [`Tcl.unsetvar`](@ref).

"""
function setvar end

const setvar_default_flags = (TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG);

for (name, decl) in ((:name,)         => (:(name::Name),),
                     (:part1, :part2) => (:(part1::Name), :(part2::Name)))
    @eval begin
        function setvar($(decl...), value; kwds...)
            return setvar(TclInterp(), $(name...), value; kwds...)
        end
        function setvar(::Type{T}, $(decl...), value; kwds...) where {T}
            return setvar(T, TclInterp(), $(name...), value; kwds...)
        end
        function setvar(interp::TclInterp, $(decl...), value; kwds...)
            return setvar(Nothing, interp, $(name...), value; kwds...)
        end
        function setvar(::Type{T}, interp::TclInterp, $(decl...), value;
                        flags::Integer = setvar_default_flags) where {T}
            # Preserve the interpreter from being garbage collected to ensure the validity
            # of the new variable value. Also preserve the name part(s) and the value from
            # being deleted while calling `unsafe_setvar`.
            GC.@preserve interp $(name...) value begin
                new_value_ptr = unsafe_setvar(interp, $(name...), value, flags)
                isnull(new_value_ptr) && setvar_error(interp, $(name...), flags)
                if T == Nothing
                    return nothing
                else
                    return unsafe_get(T, new_value_ptr)
                end
            end
        end
        @noinline function setvar_error(interp::TclInterp, $(decl...), flags::Integer)
            local mesg
            if iszero(flags & TCL_LEAVE_ERR_MSG)
                varname = variable_name($(name...))
                mesg = "cannot set Tcl variable \"$varname\""
            else
                mesg = get(String, interp)
            end
            throw(TclError(mesg))
        end
    end
end

"""
    Tcl.unsetvar([interp,] name)
    Tcl.unsetvar([interp,] part1, part2)

Delete global variable `name` or `part1(part2)` in Tcl interpreter `interp` or in the shared
interpreter of the thread if this argument is omitted.

# Keywords

Keyword `nocomplain` can be set true to ignore errors. By default, `nocomplain=false`.

Keyword `flag` can be set with bits such as `TCL_GLOBAL_ONLY` (set by default) and
`TCL_LEAVE_ERR_MSG` (set by default unless `nocomplain` is true).

# See also

[`Tcl.getvar`](@ref), [`Tcl.exists`](@ref), and [`Tcl.setvar`](@ref).

"""
function unsetvar end

function unsetvar_default_flags(nocomplain::Bool)
    return nocomplain ? TCL_GLOBAL_ONLY : (TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
end

for (name, (decl, unset)) in ((:name,)         => ((:(name::Name),),
                                                   :(Glue.Tcl_UnsetVar)),
                              (:part1, :part2) => ((:(part1::Name), :(part2::Name)),
                                                   :(Glue.Tcl_UnsetVar2)))
    @eval begin

        unsetvar($(decl...); kwds...) = unsetvar(TclInterp(), $(name...); kwds...)

        # In <tcl.h> unsetting a variable requires its name part(s) as string(s).
        function unsetvar(interp::TclInterp, $(decl...); nocomplain::Bool = false,
                          flags::Integer = unsetvar_default_flags(nocomplain))
            status = $unset(interp, $(name...), flags)
            status == TCL_OK || nocomplain || unsetvar_error(interp, $(name...), flags)
            return nothing
        end

        @noinline function unsetvar_error(interp::TclInterp, $(decl...), flags::Integer)
            local mesg
            if iszero(flags & TCL_LEAVE_ERR_MSG)
                varname = variable_name($(name...))
                mesg = "Tcl variable \"$varname\" does not exist"
            else
                mesg = get(String, interp)
            end
            throw(TclError(mesg))
        end
    end
end

"""
    Tcl.unsafe_getvar(interp, name, flags) -> value_ptr
    Tcl.unsafe_getvar(interp, part1, part2, flags) -> value_ptr

Private function to get the value of a Tcl variable. Return a pointer `value_ptr` to the Tcl
object storing the value or *null* if the variable does not exists.

This method is *unsafe* because the pointer `value_ptr` to the variable value is only valid
while the interpreter is not deleted. Furthermore, the variable name part(s) must be valid.
Hence, the caller shall have preserved the interpreter and the variable name part(s) from
being deleted.

# See also

[`Tcl.getvar`](@ref), [`Tcl.exists`](@ref), and [`Tcl.unsafe_setvar`](@ref).

"""
function unsafe_getvar end

# Private function `unsafe_getvar` is called to fetch a Tcl variable and get a value pointer
# which may be NULL if variable does not exist, otherwise its reference count is left
# unchanged.
#
# We always call Tcl_ObjGetVar2 to fetch a variable value because it is the most efficient.
# We have to take care of converting variable name parts to temporary Tcl objects as needed
# and manage their reference counts.

function unsafe_getvar(interp::TclInterp, name::FastString, flags::Integer)
    return Glue.Tcl_GetVar2Ex(interp, name, C_NULL, flags)
end

function unsafe_getvar(interp::TclInterp, name::Name, flags::Integer)
    GC.@preserve interp name begin
        interp_ptr = checked_pointer(interp)
        name_ptr = unsafe_incr_refcnt(unsafe_objptr_from(name, "Tcl variable name"))
        value_ptr = Glue.Tcl_ObjGetVar2(interp_ptr, name_ptr, null(ObjPtr), flags)
        unsafe_decr_refcnt(name_ptr)
        return value_ptr
    end
end

function unsafe_getvar(interp::TclInterp, part1::FastString, part2::FastString,
                     flags::Integer)
    return Glue.Tcl_GetVar2Ex(interp, part1, part2, flags)
end

function unsafe_getvar(interp::TclInterp, part1::Name, part2::Name, flags::Integer)
    # In a comment of Tcl C code for `Tcl_ObjGetVar2`, it is written that "Callers must incr
    # part2Ptr if they plan to decr it."
    GC.@preserve interp part1 part2 begin
        interp_ptr = checked_pointer(interp)
        local part1_ptr, part2_ptr
        stage = 0 # counter to memorize which arguments are to be released
        try
            # Retrieve pointers and increment reference counts.
            part1_ptr = unsafe_incr_refcnt(unsafe_objptr_from(part1, "Tcl array name"))
            stage = 1
            part1_ptr = unsafe_incr_refcnt(unsafe_objptr_from(part2, "Tcl array index"))
            stage = 2
            # Call C function.
            return Glue.Tcl_ObjGetVar2(interp_ptr, part1_ptr, part2_ptr, flags)
        finally
            # Decrement reference counts.
            stage ≥ 1 && unsafe_decr_refcnt(part1_ptr)
            stage ≥ 2 && unsafe_decr_refcnt(part2_ptr)
        end
    end
end

"""
    Tcl.unsafe_setvar(interp, name, value, flags) -> new_value_ptr
    Tcl.unsafe_setvar(interp, part1, part2, value, flags) -> new_value_ptr

Private function to set a Tcl variable. Return a pointer `new_value_ptr` to the Tcl object
storing the value of the variable after being set or *null* in case of failure.

This method is *unsafe* because the pointer `new_value_ptr` to the new variable value is
only valid while the interpreter is not deleted. Furthermore, the variable name part(s) and
the value must be valid. Hence, the caller shall have preserved the interpreter, the
variable name part(s) and the value from being deleted.

# See also

[`Tcl.setvar`](@ref) and [`Tcl.unsafe_getvar`](@ref).

"""
function unsafe_setvar end

# `unsafe_setvar` always calls `Tcl_ObjSetVar2` and is similar to
# [`Tcl.unsafe_getvar`](@ref) for managing arguments.

function unsafe_setvar(interp::TclInterp, name::Name, value, flags::Integer)
    interp_ptr = checked_pointer(interp)
    local name_ptr, value_ptr
    stage = 0 # counter to memorize which arguments are to be released
    try
        # Retrieve pointers and increment reference counts.
        name_ptr = unsafe_incr_refcnt(unsafe_objptr_from(name, "Tcl variable name"))
        stage = 1
        value_ptr = unsafe_incr_refcnt(unsafe_objptr_from(value, "Tcl variable value"))
        stage = 2
        # Call C function.
        return Glue.Tcl_ObjSetVar2(interp_ptr, name_ptr, null(ObjPtr), value_ptr, flags)
    finally
        # Decrement reference counts.
        stage ≥ 1 && unsafe_decr_refcnt(name_ptr)
        stage ≥ 2 && unsafe_decr_refcnt(value_ptr)
    end
end

function unsafe_setvar(interp::TclInterp, part1::Name, part2::Name, value, flags::Integer)
    interp_ptr = checked_pointer(interp)
    local part1_ptr, part2_ptr, value_ptr
    stage = 0 # counter to memorize which arguments are to be released
    try
        # Retrieve pointers and increment reference counts.
        part1_ptr = unsafe_incr_refcnt(unsafe_objptr_from(part1, "Tcl array name"))
        stage = 1
        part2_ptr = unsafe_incr_refcnt(unsafe_objptr_from(part2, "Tcl array index"))
        stage = 2
        value_ptr = unsafe_incr_refcnt(unsafe_objptr_from(value, "Tcl array value"))
        stage = 3
        # Call C function.
        return Glue.Tcl_ObjSetVar2(interp_ptr, part1_ptr, part2_ptr, value_ptr, flags)
    finally
        # Decrement reference counts.
        stage ≥ 1 && unsafe_decr_refcnt(part1_ptr)
        stage ≥ 2 && unsafe_decr_refcnt(part2_ptr)
        stage ≥ 3 && unsafe_decr_refcnt(value_ptr)
    end
end

# Yield a pointer to a Tcl object from 1st argument. 2nd argument describe the argument.
function unsafe_objptr_from(obj::TclObj, mesg::AbstractString)
    ptr = pointer(obj)
    isnull(ptr) && unexpected_null(mesg)
    return ptr
end
unsafe_objptr_from(val::Any, mesg::AbstractString) = new_object(val)
