"""
     Tcl.list(args...) -> lst
     interp.list(args...) -> lst

Build a list `lst` of Tcl objects such that each of `args...` is a single element of `lst`.
This mimics the behavior of the Tcl `list` command.

In the second above example, `interp` is a Tcl interpreter used to retrieve an error message
in case of failure.

# See also

[`Tcl.concat`](@ref), [`Tcl.eval`](@ref), [`TclObj`](@ref), and [`TclInterp`](@ref).

"""
function list end

"""
    Tcl.concat(args...) -> lst
    interp.concat(args...) -> lst

Build a list of Tcl objects obtained by concatenating the elements of the arguments
`arg...` each being considered as a list. This mimics the behavior of the Tcl `concat`
command.

In the second above example, `interp` is a Tcl interpreter used to retrieve a more
informative error message in case of error.

# Pairs

In `args...`, `key => val` pairs where `key` is a symbol or a string are treated specially
by `Tcl.concat`: they give the two elements `\"-\$(key)\"` and `val` in the output list.
This is intended for specifying Tk widget options in a readable Julia style.

# See also

[`Tcl.list`](@ref), [`Tcl.eval`](@ref), [`TclObj`](@ref), and [`TclInterp`](@ref).

"""
function concat end

for (func, append) in (:list   => :unsafe_append_element,
                       :concat => :unsafe_append_list,
                       )
    @eval begin
        $func(args...) = _TclObj(new_list($append, args...))
        function $func(interp::TclInterp, args...)
            GC.@preserve interp begin
                return _TclObj(new_list($append, checked_pointer(interp), args...))
            end
        end
    end
end

_getproperty(interp::TclInterp, ::Val{:list}) = PrefixedFunction(list, interp)
_getproperty(interp::TclInterp, ::Val{:concat}) = PrefixedFunction(concat, interp)

@noinline invalid_list() =
    throw(TclError("Tcl object is not a valid list"))

Base.IteratorSize(::Type{TclObj}) = Base.HasLength()
function Base.length(list::TclObj)
    len = Ref{Cint}()
    status = Tcl_ListObjLength(null(InterpPtr), list, len)
    status == TCL_OK || invalid_list()
    return Int(len[])::Int
end

# When iterated or indexed, a Tcl object yield Tcl objects.
Base.IteratorEltype(::Type{TclObj}) = Base.HasEltype()
Base.eltype(::Type{TclObj}) = TclObj

Base.firstindex(list::TclObj) = 1
Base.lastindex(list::TclObj) = length(list)

Base.first(list::TclObj) = list[firstindex(list)]
Base.last(list::TclObj) = list[lastindex(list)]

function Base.getindex(list::TclObj, index::Integer)
    if index ≥ 𝟙
        objref = Ref{ObjPtr}()
        status = Tcl_ListObjIndex(null(InterpPtr), list, index - 𝟙, objref)
        status == TCL_OK || invalid_list()
        objptr = objref[]
        isnull(objptr) || return _TclObj(objptr)
    end
    return missing
end

function Base.getindex(list::TclObj, indices::AbstractVector{<:Integer})
    GC.@preserve list begin
        objc, objv = unsafe_get_list_elements(checked_pointer(list))
        result = new_list()
        try
            for index in indices
                𝟙 ≤ index ≤ objc || error(
                    "attempt to index $(objc)-element Tcl list at index $i")
                unsafe_append_element(result, unsafe_load(objv, index))
            end
        catch
            Tcl_DecrRefCount(result)
            rethrow()
        end
        return _TclObj(result)
    end
end

function Base.getindex(list::TclObj, flags::AbstractVector{Bool})
    GC.@preserve list begin
        objc, objv = unsafe_get_list_elements(checked_pointer(list))
        len = length(flags)
        len == objc || throw(DimensionMismatch(
            "attempt to index $(objc)-element Tcl list by $(len)-element vector of `Bool`"))
        result = new_list()
        offset = firstindex(flag) - 1
        try
            for index in 𝟙:objc
                if flags[index + offset]
                    unsafe_append_element(result, unsafe_load(objv, index))
                end
            end
        catch
            Tcl_DecrRefCount(result)
            rethrow()
        end
        return _TclObj(result)
    end
end

# NOTE Julia `push!` is similar to Tcl `lappend` command.
function Base.push!(list::TclObj, args...)
    GC.@preserve list begin
        listptr = pointer(list)
        for arg in args
            unsafe_append_element(listptr, arg)
        end
    end
    return list
end

# NOTE Julia `append!` is similar to Tcl `concat` command.
function Base.append!(list::TclObj, args...)
    GC.@preserve list begin
        listptr = pointer(list)
        for arg in args
            unsafe_append_list(listptr, arg)
        end
    end
    return list
end

struct ListIterator
    parent::TclObj # to hold a reference on the parent list
    objc::Int
    objv::Ptr{ObjPtr}
    function ListIterator(list::TclObj)
        GC.@preserve list begin
            objc, objv = unsafe_get_list_elements(checked_pointer(list))
            return new(list, objc, objv)
        end
    end
end

function Base.iterate(list::TclObj,
                      (iter, index)::Tuple{ListIterator,Int} = (ListIterator(list), 1))
    1 ≤ index ≤ iter.objc || return nothing
    parent = iter.parent
    GC.@preserve parent begin
        item = _TclObj(unsafe_load(iter.objv, index))
        return item, (iter, index + 1)
    end
end

unsafe_get_list_elements(list::ObjPtr) = unsafe_get_list_elements(null(InterpPtr), list)
function unsafe_get_list_elements(interp::InterpPtr, list::ObjPtr)
    objc = Ref{Cint}()
    objv = Ref{Ptr{ObjPtr}}()
    status = Tcl_ListObjGetElements(interp, list, objc, objv)
    status == TCL_OK || unsafe_error(interp, "failed to retrieve Tcl list elements")
    return Int(objc[])::Int, objv[]
end

# NOTE With `index ≤ 0`, value is inserted at the beginning of the list. With `index >
# length(list)`, `value` is appended to the end of the list.
function Base.setindex!(list::TclObj, value, index::Integer)
    GC.@preserve list value begin
        obj = Tcl_IncrRefCount(
            if value isa TclObj
                checked_pointer(value)
            else
                new_object(value)
            end)
        try
            unsafe_replace_list(pointer(list), index - 1, 1, 1, Ref(obj))
        finally
            Tcl_DecrRefCount(obj)
        end
    end
    return list
end

function Base.delete!(list::TclObj, index::Integer)
    if index ≥ 𝟙
        GC.@preserve list begin
            unsafe_replace_list(pointer(list), index - 𝟙, 1, 0, C_NULL)
        end
    end
    return list
end

# NOTE In `Tcl_ListObjReplace`:
#
# * If `first ≥ length(list)`, no elements are deleted and the objects in `objv` are
#   appended to the list.
#
# * If `first ≤ 0` it is assumed to be `0`, that is the index of the first list element.
#
# * If `count ≤ 0` or `first ≥ length(list)`, no elements are deleted.
#
# * The objects in `objv` are inserted before index `first` replacing the `count` elements
#   of the list initially stored at and after index `first`.
#
# Thus, `Tcl_ListObjReplace` can be used to append, prepend, or insert elements and, at the
# same time, possibly delete elements.
#
function unsafe_replace_list(list::ObjPtr, first::Integer,
                             count::Integer, objc::Integer, objv)
    unsafe_replace_list(null(InterpPtr), list, first, count, objc, objv)
end

function unsafe_replace_list(interp::InterpPtr, list::ObjPtr, first::Integer,
                             count::Integer, objc::Integer, objv)
    assert_writable(list) # required by copy-on-write policy
    status = Tcl_ListObjReplace(interp, list, first, count, objc, objv)
    status == TCL_OK || unsafe_error(interp, "failed to replace Tcl list element(s)")
    return nothing
end

"""
    Tcl.Private.new_list() -> lstptr

Return a pointer to a Tcl object storing an empty list.

    Tcl.Private.new_list(f, [interp,] args...) -> lstptr

Return a pointer to a Tcl object storing a list built by calling `f(interp, list, arg)` for
each `arg` in `args...`. Typically, `f` is [`Tcl.Private.unsafe_append_element`](@ref) or
[`Tcl.Private.unsafe_append_list`](@ref).

Optional argument `interp` is a Tcl interpreter that can be used to retrieve the error
message in case of failure.

!!! warning
    The returned object is not managed and has a zero reference count. The caller is
    responsible of taking care of that.

"""
new_list() = Tcl_NewListObj(0, C_NULL)

new_list(f::Function, args...) = unsafe_new_list(f, null(InterpPtr), args...)

function new_list(f::Function, interp::TclInterp, args...)
    GC.@preserve interp begin
        return unsafe_new_list(f, checked_pointer(interp), args...)
    end
end

# Build a list from a given vector of of objects.

function new_list(objc::Integer, objv::Ptr{Ptr{Tcl_Obj}})
    return new_list(unsafe_append_element, objc, objv)
end

function new_list(f::Function, objc::Integer, objv::Ptr{Ptr{Tcl_Obj}})
    return unsafe_new_list(f, null(InterpPtr), objc, objv)
end

function new_list(interp::TclInterp, objc::Integer, objv::Ptr{Ptr{Tcl_Obj}})
    return new_list(unsafe_append_element, interp, objc, objv)
end

function new_list(f::Function, interp::TclInterp, objc::Integer, objv::Ptr{Ptr{Tcl_Obj}})
    GC.@preserve interp begin
        return unsafe_new_list(f, null_or_checked_pointer(interp), objc, objv)
    end
end

"""
    Tcl.Private.unsafe_new_list(f, interp, args...) -> lstptr

Unsafe method called by [`Tcl.Private.new_list`](@ref) to build its result. Argument `interp` is a
pointer to a Tcl interpreter. If `interp` is non-null, it is used to retrieve the error
message in case of failure.

!!! warning
    Unsafe: If `interp` is specified and non-null, it must be valid during the call of the
    `unsafe_new_list` method.

"""
function unsafe_new_list(f::Function, interp::InterpPtr, args...)
    list = new_list()
    try
        for arg in args
            f(interp, list, arg)
        end
    catch
        Tcl_DecrRefCount(list) # free list object
        rethrow()
    end
    return list
end

function unsafe_new_list(f::Function, interp::InterpPtr,
                         objc::Integer, objv::Ptr{Ptr{Tcl_Obj}})
    list = new_list()
    try
        for i in 1:objc
            f(interp, list, unsafe_load(objv, i))
        end
    catch
        Tcl_DecrRefCount(list)
        rethrow()
    end
    return list
end

# Appending a new item to a list with `Tcl_ListObjAppendElement` or `Tcl_ListObjAppendList`
# increments the reference count of the item, this is the only side effect for the item.
# That is to say, the appended item is not duplicated, just shared. So, to manage the memory
# associated with the item, we can increment its reference count before appending and
# decrement it after with no measurable effects on the performances (but useful to free
# object in case of errors). Incrementing and decrementing the reference count is not
# necessary for a managed object but such an object must be preserved from being garbage
# collected.

"""
    Tcl.Private.unsafe_append_element([interp,] list, item) -> nothing

Private method to append `item` as a single element to the Tcl object `list`.

Optional argument `interp` is a pointer to a Tcl interpreter. If `interp` is specified and
non-null, it is used to retrieve the error message in case of failure.

The following conditions are asserted: `list` must be *writable* (i.e., a non-null pointer
to a non-shared Tcl object) and `item` must be *readable* (i.e., a non-null pointer to a Tcl
object).

!!! warning
    Unsafe method: `list`, `item`, and `interp` (the latter if non-null) must remain valid
    during the call to this method (e.g., preserved from being garbage collected).

!!! warning
    The method may throw and the caller is responsible of managing the reference count of
    `item` to have it automatically deleted in case of errors if it is fresh object created
    by `new_object(val)`.

# See also

[`Tcl.Private.unsafe_append_list`](@ref) and [`Tcl.Private.new_list`](@ref).

"""
function unsafe_append_element end

"""
    Tcl.Private.unsafe_append_list([interp,] list, iter) -> nothing

Private method to concatenate the elements of `iter` to the end of the Tcl object `list`.

# See also

[`Tcl.Private.unsafe_append_element`](@ref) and [`Tcl.Private.new_list`](@ref).

"""
function unsafe_append_list end

for (jl, (c, mesg)) in (:unsafe_append_element => (:(Tcl_ListObjAppendElement),
                                                   "failed to append item to Tcl list"),
                        :unsafe_append_list => (:(Tcl_ListObjAppendList),
                                                "failed to concatenate list to Tcl list"),
                        )
    @eval begin
        $jl(list::ObjPtr, arg) = $jl(null(InterpPtr), list, arg)

        function $jl(interp::InterpPtr, list::ObjPtr, obj::ObjPtr)
            assert_writable(list) # required by copy-on-write policy
            assert_readable(obj) # must be non-null
            status = $c(interp, list, obj)
            status == TCL_OK || unsafe_error(interp, $mesg)
            return nothing
        end

        function $jl(interp::InterpPtr, list::ObjPtr, arg)
            obj = Tcl_IncrRefCount(new_object(arg))
            try
                $jl(interp, list, obj)
            finally
                Tcl_DecrRefCount(obj)
            end
            return nothing
        end

        function $jl(interp::InterpPtr, list::ObjPtr, obj::TclObj)
            GC.@preserve obj begin
                $jl(interp, list, pointer(obj))
            end
            return nothing
        end

        function $jl(interp::InterpPtr, list::ObjPtr, func::Function)
            @warn "Appending a callback is not yet implemented"
            return nothing
            # Setting a callback involves (i) passing the name of the corresponding Tcl
            # command and (ii) creating this command in the target interpreter if it does
            # not exists.
        end
    end
end

# With a pair, `unsafe_append_list` appends a pair `key => val` as a command line flag with
# value as for Tk widgets.

function unsafe_append_list(interp::InterpPtr, list::ObjPtr,
                            (key,val)::Pair{<:Union{AbstractString,Symbol},<:Any})
    unsafe_append_list(interp, list, String(key) => val)
    return nothing
end

function unsafe_append_list(interp::InterpPtr, list::ObjPtr,
                            (key,val)::Pair{String,<:Any})
    unsafe_append_element(interp, list, "-"*string(key))
    unsafe_append_element(interp, list, val)
    return nothing
end

function unsafe_append_list(interp::InterpPtr, list::ObjPtr, iter::Tuple)
    for x in iter
        unsafe_append_element(interp, list, x)
    end
    return nothing
end
