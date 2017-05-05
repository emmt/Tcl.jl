# Management of Tcl lists

"""
    Tcl.escape(c)

yields whether the character `c` should be escaped to form a single Tcl
argument or list element.

"""
@inline escape(c::Char) = (isspace(c) || c == '\\' || c == '[' || c == ']'
                           || c == '{' || c == '}' || c == '$')

# A Tcl list is just a dynamic buffer of characters build up in such a way that
# it produces a valid Tcl list when converted to a string.

type TclList
    arr::Vector{Char}
    len::Int
end

const LISTCHUNK = 200

"""
    Tcl.roundup(a, b)

yields integer `a` rounded up to a multiple of integer `b`.  The two arguments
must be nonnegative and `b` must be stricty positive.

"""
roundup(a::Integer, b::Integer) = div(b - 1 + a, b)*b

TclList(len::Integer = LISTCHUNK) =
    TclList(sizehint!(Array{Char}(roundup(len, LISTCHUNK)), LISTCHUNK), 0)

function reset!(lst::TclList)
    lst.len = 0
    return lst
end

@inline function grow!(lst::TclList, n::Integer)
    n0 = length(lst.arr)
    n1 = lst.len + n
    if n0 < n1
        resize!(lst.arr, roundup(max(n1, n0 + div(n0, 2)), LISTCHUNK))
    end
    return lst
end

Base.string(lst::TclList) = convert(String, lst)
Base.convert(::Type{String}, lst::TclList) = convert(String, lst.arr[1:lst.len])
Base.convert(::Type{TclList}, lst::TclList) = lst
Base.eltype(::TclList) = T
Base.ndims(::TclList) = 1
Base.size(lst::TclList) = (lst.len,)
Base.length(lst::TclList) = lst.len
Base.getindex(lst::TclList, i) = lst.arr[i]
Base.setindex!(lst::TclList, value, i) = setindex!(lst.arr, value, i)
Base.start(lst::TclList) = 1
Base.last(lst::TclList) = lst.len
Base.linearindexing(lst::TclList) = LinearFast()
Base.linearindices(lst::TclList) = OneTo(lst.len)
capacity(lst::TclList) = length(lst.arr)
available(lst::TclList) = capacity(lst) - length(lst)
Base.show(io::IO, lst::TclList) = show(io, string(lst))

@inline function __append!(buf::Vector{Char}, str::AbstractString, j::Int)
    for c in str
        if escape(c)
            j += 2
            buf[j-1] = '\\'
        else
            j += 1
        end
        buf[j] = c
    end
    return j
end

function list(str::AbstractString)
    lst = TclList(2*length(str))
    lst.len = __append!(lst.arr, str, last(lst))
    return lst
end

list(val::Union{Real,Symbol}) = list(__string(val))

list(arg0, args...) = lappend!(list(arg0), args...)

lappend!(lst::TclList, val::Union{Real,Symbol}) = lappend!(lst, __string(val))

function lappend!(lst::TclList, args...)
    for arg in args
        lappend!(lst, arg)
    end
    return lst
end

function lappend!(lst::TclList, str::AbstractString)
    grow!(lst, 1 + 2*length(str))
    @inbounds begin
        j = last(lst) + 1
        lst[j] = ' '
        lst.len = __append!(lst.arr, str, j)
    end
    return lst
end
