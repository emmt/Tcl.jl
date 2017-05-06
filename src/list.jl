# Management of Tcl lists

# A Tcl list is just a dynamic buffer of characters build up in such a way that
# it produces a valid Tcl list when converted to a string.

type TclList
    arr::Vector{Char}
    len::Int
end

"""
    tclrepr(arg) :: String

yields a textual representation of `arg` which can be used in Tcl scripts ot
commands.  This method may be overloaded to implement means to pass other kinds
of arguments to Tcl.  The returned value **must** be of a type derived from
`AbstractString`.  Note that `Tcl.evaluate` and similar will take care of
escaping special characters so spaces, braces, etc. can be present in the
returned string.

"""
@inline tclrepr(::Void) = EMPTY
@inline tclrepr(val::AbstractString) = val
@inline tclrepr(val::Symbol) = string(val)
# Note that `string(val)` is about twice as fast as `@sprintf "%d" val`
@inline tclrepr(val::Union{Integer,Cdouble,VersionNumber}) = string(val)
@inline tclrepr(val::AnyFloat) = string(Cdouble(val))
@inline tclrepr(lst::TclList) =
    tclerror("calling `tclrepr` on `TclList` is forbidden")


"""
    Tcl.escape(c)

yields whether the character `c` should be escaped to form a single Tcl
argument or list element.

"""
@inline escape(c::Char) = (isspace(c) || c == '\\' || c == '[' || c == ']'
                           || c == '{' || c == '}' || c == '$')

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

"""
    Tcl.list(arg0, args...; kwds...)

yields a textual list of items consisting in the arguments `arg0`, `args...`
and followed by the keywords as pairs of `-key val`.  The result is such that
Tcl will correctly parse it as a list with one item for each argument and two
items for each keyword.  This function is intended to be a helper for
constructing valid Tcl commands.  See `Tcl.lappend!` and `Tcl.lappendoption!`
more more details.

"""
function list(str::AbstractString)
    @inbounds begin
        len = length(str)
        lst = TclList(2*max(1, len))
        if len ≥ 1
            lst.len = __append!(lst.arr, str, 0)
        else
            lst[1] = '{'
            lst[2] = '}'
            lst.len = 2
        end
        return lst
    end
end

list(arg0, args...; kwds...) = lappend!(list(tclrepr(arg0)), args...; kwds...)

"""
    Tcl.lappend!(lst, args...; kwds...) -> lst

appends arguments `args...` and keywords `kwds...` at the end of the list
`lst`.  For instance:

    Tcl.lappend!(lst, arg1, arg2, key1=val1, key2=val2)

appends the following 6 items:

    arg1 arg2 -key1 val1 -key2 val2

to the end of `lst` where all items are converted to their string
representation and with special characters escaped.  Note that keywords will
appear as the last added items (whatever their order in the call to
`Tcl.lappend!`).

"""
function lappend!(lst::TclList, args...; kwds...)
    for arg in args
        lappenditem!(lst, arg)
    end
    for kwd in kwds
        lappendoption!(lst, kwd)
    end
    return lst
end

function lappenditem!(lst::TclList, str::AbstractString)
    @inbounds begin
        len = length(str)
        grow!(lst, 1 + 2*max(1, len))
        j = last(lst) + 1
        lst[j] = ' '
        if len ≥ 1
            lst.len = __append!(lst.arr, str, j)
        else
            lst[j+1] = '{'
            lst[j+2] = '}'
            lst.len = j+2
        end
        return lst
    end
end

function lappenditem!(lst::TclList, otherlst::TclList)
    @inbounds begin
        n = length(otherlst)
        grow!(lst, 3 + n)
        j = last(lst) + 2
        lst[j-1] = ' '
        lst[j] = '{'
        for i in 1:n
            lst[j+i] = otherlst[i]
        end
        j += n+1
        lst[j] = '}'
        lst.len = j
        return lst
    end
end

lappenditem!(lst::TclList, item) = lappenditem!(lst, tclrepr(item))

"""
    Tcl.lappendoption!(lst, (opt, val)) -> lst

appends a single option-value pair at the end of the list `lst`.  Option `opt`
is a `Symbol` and value `val` is anything that can be put in a form
understandable by Tcl.  Two *items* are added at the end of the list:

    -option value

where `option` and `value` are respectively `opt` and `val` converted to their
string representation and with special characters escaped. (Note the leading
hyphen.)

"""
lappendoption!{T}(lst::TclList, spec::Tuple{Symbol,T}) =
    lappendoption!(lst, tclrepr(spec[1]), tclrepr(spec[2]))

function lappendoption!(lst::TclList, opt::AbstractString, val::AbstractString)
    @inbounds begin
        len1 = length(opt)
        len2 = length(val)
        grow!(lst, 3 + 2*max(1, len1) + 2*max(1, len2))
        j = last(lst)
        lst[j+1] = ' '
        lst[j+2] = '-'
        if len1 ≥ 1
            j = __append!(lst.arr, opt, j+2)
        else
            lst[j+3] = '{'
            lst[j+4] = '}'
            j += 4
        end
        lst[j+1] = ' '
        if len2 ≥ 1
            lst.len = __append!(lst.arr, val, j+1)
        else
            lst[j+2] = '{'
            lst[j+3] = '}'
            lst.len = j+3
        end
        return lst
    end
end
