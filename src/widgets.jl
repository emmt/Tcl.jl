#
# widgets.jl -
#
# Implement Tk (and TTk) widgets
#

"""
    @TkWidget type class command prefix

Define structure `type` for widget `class` based on Tk `command` and using `prefix` for
automatically defined widget names. If `prefix` starts with a dot, a top-level widget is
assumed. `class` is the class name as given by the Tk command `winfo class \$w` and is
needed to uniquely identify Julia widget type given its Tk class. For now, `command` and
`prefix` must be string literals.

"""
macro TkWidget(_type, class, command, prefix)

    type = esc(_type) # constructor must be in the caller's module
    class isa Union{Symbol,String} || error("`class` must be a symbol or a string literal")
    class isa String || (class = String(class)::String)
    command isa String || error("`command` must be a string literal")
    prefix isa String || error("`prefix` must be a string literal")

    if first(prefix) == '.'
        # Root (top-level) widget.
        quote
            struct $type <: TkRootWidget
                interp::TclInterp
                path::TclObj # Tk window path and Tcl widget command
                function $type(interp::TclInterp, name::Name, pairs::Pair...)
                    # It is sufficient to ensure that Tk is loaded for root widgets because
                    # other widgets must have a parent.
                    tk_start(interp)
                    path = create_widget(
                        $type, interp, $command, widget_path(name), pairs...)
                    return new(interp, path)
                end
            end

            # Provide optional arguments.
            $type(pairs::Pair...) = $type(TclInterp(), pairs...)
            $type(name::Name, pairs::Pair...) = $type(TclInterp(), name, pairs...)
            $type(interp::TclInterp, pairs::Pair...) =
                $type(interp, widget_auto_name(interp, nothing, $prefix), pairs...)

            # Make the widget callable.
            (w::$type)(args...; kwds...) = exec(w, args...; kwds...)

            # Register widget class.
            register_widget_class($class, $type)
        end
    else
        # Other (top-level) widget.
        quote
            struct $type <: TkWidget
                parent::TkWidget
                interp::TclInterp
                path::TclObj # Tk window path and Tcl widget command
                function $type(parent::TkWidget, child::Name, pairs::Pair...)
                    interp = parent.interp
                    path = create_widget(
                        $type, interp, $command, widget_path(parent, child), pairs...)
                    return new(parent, interp, path)
                end
            end

            # Provide optional arguments.
            $type(parent::Union{TkWidget,Name}, pairs::Pair...) =
                $type(parent, widget_auto_name(interp, parent, $prefix), pairs...)

            # Get widget for parent.
            $type(parent::Name, child::Name, pairs::Pair...) =
                $type(TkWidget(parent), child, pairs...)

            # Make the widget callable.
            (w::$type)(args...; kwds...) = exec(w, args...; kwds...)

            # Register widget class.
            register_widget_class($class, $type)
        end
    end
end

const widget_classes = Dict{String,Type{<:TkWidget}}()

function register_widget_class(class::String, ::Type{T}) where {T<:TkWidget}
    if haskey(widget_classes, class)
        S = widget_classes[class]
        isequal(S, T) || error("attempt to register widget class `$class` for type `$T` ",
                               "while already registered for type `$S`")
    else
        widget_classes[class] = T
    end
    return nothing
end

const auto_name_counter = UInt64[]

function widget_auto_name(interp::TclInterp, parent::Union{TkWidget,Nothing},
                          prefix::String)
    root = isnothing(parent) ? nothing : String(parent.path)::String
    while true
        name = auto_name(prefix)
        path = compose_widget_path(root, name)
        interp.exec(Bool, :winfo, :exists, path) || return name
    end
end

function widget_constructor_from_path(interp::TclInterp, path::Name)
    return widget_constructor_from_class(winfo_class(interp, path))
end

function widget_constructor_from_class(class::Name)
    # In the database of widget classes, the class is a string.
    class isa String || (class = String(class)::String)
    constructor = get(widget_classes, class, nothing)
    isnothing(constructor) && argument_error("unregistered widget class \"$class\"")
    return constructor
end

# Top-level widgets.
@TkWidget TkToplevel      Toplevel      "::toplevel"          ".top"
@TkWidget TkMenu          Menu          "::menu"              ".mnu"

# Tk widgets.
@TkWidget TkButton        Button        "::button"            "btn"
@TkWidget TkCanvas        Canvas        "::canvas"            "cnv"
@TkWidget TkCheckbutton   Checkbutton   "::checkbutton"       "cbt"
@TkWidget TkEntry         Entry         "::entry"             "ent"
@TkWidget TkFrame         Frame         "::frame"             "frm"
@TkWidget TkLabel         Label         "::label"             "lab"
@TkWidget TkLabelframe    Labelframe    "::labelframe"        "lfr"
@TkWidget TkListbox       Listbox       "::listbox"           "lbx"
@TkWidget TkMenubutton    Menubutton    "::menubutton"        "mbt"
@TkWidget TkMessage       Message       "::message"           "msg"
@TkWidget TkPanedwindow   Panedwindow   "::panedwindow"       "pwn"
@TkWidget TkRadiobutton   Radiobutton   "::radiobutton"       "rbt"
@TkWidget TkScale         Scale         "::scale"             "scl"
@TkWidget TkScrollbar     Scrollbar     "::scrollbar"         "sbr"
@TkWidget TkSpinbox       Spinbox       "::spinbox"           "sbx"
@TkWidget TkText          Text          "::text"              "txt"

# Ttk (Themed Tk) widgets.
@TkWidget TtkButton       TButton       "::ttk::button"       "btn"
@TkWidget TtkCheckbutton  TCheckbutton  "::ttk::checkbutton"  "cbt"
@TkWidget TtkCombobox     TCombobox     "::ttk::combobox"     "cbx"
@TkWidget TtkEntry        TEntry        "::ttk::entry"        "ent"
@TkWidget TtkFrame        TFrame        "::ttk::frame"        "frm"
@TkWidget TtkLabel        TLabel        "::ttk::label"        "lab"
@TkWidget TtkLabelframe   TLabelframe   "::ttk::labelframe"   "lfr"
@TkWidget TtkMenubutton   TMenubutton   "::ttk::menubutton"   "mbt"
@TkWidget TtkNotebook     TNotebook     "::ttk::notebook"     "nbk"
@TkWidget TtkPanedwindow  TPanedwindow  "::ttk::panedwindow"  "pwn"
@TkWidget TtkProgressbar  TProgressbar  "::ttk::progressbar"  "pgb"
@TkWidget TtkRadiobutton  TRadiobutton  "::ttk::radiobutton"  "rbt"
@TkWidget TtkScale        TScale        "::ttk::scale"        "scl"
@TkWidget TtkScrollbar    TScrollbar    "::ttk::scrollbar"    "sbr"
@TkWidget TtkSeparator    TSeparator    "::ttk::separator"    "sep"
@TkWidget TtkSizegrip     TSizegrip     "::ttk::sizegrip"     "szg"
@TkWidget TtkSpinbox      TSpinbox      "::ttk::spinbox"      "sbx"
@TkWidget TtkTreeview     TTreeview     "::ttk::treeview"     "trv"

# Window "." has a special class in Tk.
register_widget_class("Tk", TkToplevel)

"""
    TkWidget(interp=TclInterp(), path)

Return a widget for the given Tk window `path` in interpreter `interp`. The type of the
widget is inferred from the class of the Tk window.

"""
TkWidget(path::Name, interp::TclInterp = TclInterp()) = TkWidget(interp, path)
function TkWidget(interp::TclInterp, path::Name)
    # The following requires that `path` be a Tcl object or a string, not a symbol.
    (path isa Union{AbstractString,TclObj}) || (path = String(path)::String)
    winfo_exists(interp, path) || argument_error(
        "\"$path\" is not the path of an existing Tk widget")
    # Now we can get the widget class and hence find its registered constructor.
    return _TkWidget(widget_constructor_from_path(interp, path), interp, path)
end

# Private method to dispatch on constructor `T`.
function _TkWidget(::Type{T}, interp::TclInterp, path::Name) where {T<:TkWidget}
    # Retrieve parent path.
    parent = winfo_parent(interp, path)
    # Top-level widgets have no parents.
    parent ∈ ("", ".") && return T(interp, path)
    # For other widgets, we need to create all ancestors.
    return T(TkWidget(interp, parent), winfo_name(interp, path))
end

winfo_exists(w::TkWidget) = winfo_exists(w.interp, w.path)
winfo_exists(interp::TclInterp, path::Name) = interp.exec(Bool, :winfo, :exists, path)

winfo_parent(w::TkWidget) = winfo_parent(w.interp, w.path)
winfo_parent(interp::TclInterp, path::Name) = interp.exec(:winfo, :parent, path)

winfo_name(w::TkWidget) = winfo_name(w.interp, w.path)
winfo_name(interp::TclInterp, path::Name) = interp.exec(:winfo, :name, path)

winfo_class(w::TkWidget) = winfo_class(w.interp, w.path)
function winfo_class(interp::TclInterp, path::Name)
    # `winfo class .` yields the name of the application which is not what we want. So, we
    # must specifically consider the case of the "." window.
    return winfo_isroot(path) ? TclObj(:Toplevel) : interp.exec(:winfo, :class, path)
    # TODO for Tix widgets, we may instead use: class = string(interp(path, "configure -class")[4])
end

"""
    Tcl.Private.winfo_isroot(w) -> bool

Return whether `w` is the Tk root widget of window path.

This is to cope with that, in many situations, the case of the "." window must be considered
specifically. For example, `winfo parent .` yields an empty result while `winfo class .`
yields the name of the application.

"""
winfo_isroot(path::Symbol) = (path == :(.))
winfo_isroot(path::Name) = path == "."
winfo_isroot(w::TkToplevel) = winfo_isroot(w.path)
winfo_isroot(w::TkWidget) = false

"""
   Tcl.Private.widget_path(top, children...) -> path::String

Return a checked Tk window path.

"""
widget_path(w::TkWidget) = String(w.path)::String # TODO Base.abspath?

function widget_path(parent::TkWidget, name::Name)::String
    # Assume parent's path is valid and just check the child name.
    return compose_widget_path(parent.path, widget_name(name))
end

function widget_path(top::Name, children::Name...)::String
    dot = UInt8('.')
    buf = IOBuffer()
    start = buf.ptr
    write(buf, top)
    stop = buf.size
    index = start - 1
    for i in start:stop
        if buf.data[i] == dot
            index = i
        end
    end
    index == start || argument_error(
        "top widget name must start with a dot and contain no other dots")
    for child in children
        write(buf, dot) # write separator
        write_widget_child_name(buf, child)
    end
    return String(take!(buf))
end

# Write and check widget child name.
function write_widget_child_name(buf::IOBuffer, name::Name)
    dot = UInt8('.')
    start = buf.ptr
    write(buf, name)
    stop = buf.size
    stop ≥ start || argument_error("invalid empty widget child name")
    for i in start:stop
        buf.data[i] == dot && argument_error(
            "widget child name must not contains any dots")
    end
    return buf
end

# Check and convert widget child name.
function widget_name(name::Name)
    return String(take!(write_widget_child_name(IOBuffer(), name)))
end

# `compose_widget_path` is meant to be fast and does not check the validity of the widget
# path.
function compose_widget_path(parent::Nothing, name::Name)::String
    return String(name)
end
function compose_widget_path(parent::TkWidget, name::Name)::String
    return compose_widget_path(parent.path, name)
end
function compose_widget_path(parent::FasterString, name::FasterString)::String
    return parent == "." ? string(".", name) : string(parent, ".", name)
end
function compose_widget_path(parent::Name, name::Name)::String
    buf = IOBuffer(; sizehint = nbytes(parent) + nbytes(name) + nbytes('.'))
    # Write parent path in buffer and append a '.' separator if parent path is not "."
    # (i.e., has more than one byte).
    write(buf, parent) > 1 && write(buf, '.')
    # Append children name and return resulting string.
    write(buf, name)
    return String(take!(buf))
end

nbytes(s::Union{String,SubString{String},Symbol}) = sizeof(sym)
nbytes(c::Char) = ncodeunits(c)
function nbytes(obj::TclObj)::Int
    GC.@preserve obj begin
        ptr = pointer(obj)
        isnull(ptr) && return 0
        len = Ref{Tcl_Size}()
        Tcl_GetStringFromObj(ptr, len)
        return Int(len[])
    end
end

# Private method called to create a widget.
function create_widget(::Type{T}, interp::TclInterp, cmd::Name, path::Name,
                       pairs::Pair...) where {T}
    if winfo_exists(interp, path)
        # If widget already exists, it will be simply re-used, so we just apply
        # configuration options if any.
        W = widget_constructor_from_path(interp, path)
        W === T || argument_error(
            "attempt to call constructor `$T` on a Tk widget of type `$W`")
        widget = TclObj(path)
        if length(pairs) > 0
            status = interp.exec(TclStatus, widget, :configure, pairs...)
            status == TCL_OK || throw(TclError(interp))
        end
        return widget
    else
        # Widget does not already exists, create it with configuration options.
        status = interp.exec(TclStatus, cmd, path, pairs...)
        status == TCL_OK || throw(TclError(interp))
        return interp.result(TclObj)
    end
end

"""
    TkToplevel(interp=TclInterp(), ".")

Return the top-level Tk window for Tcl interpreter `interp`. This also takes care of loading
Tk extension in the interpreter and starting the event loop.

To create a new top-level window:

    TkToplevel(interp, path, pairs...)

""" TkToplevel

# Accessors.
TclInterp(w::TkWidget) = w.interp
Base.parent(w::TkWidget) = w.parent
Base.parent(::TkRootWidget) = nothing
TclObj(w::TkWidget) = w.path
Base.convert(::Type{TclObj}, w::TkWidget) = TclObj(w)::TclObj
get_objptr(w::TkWidget) = get_objptr(TclObj(w)) # used in `exec`

exec(w::TkWidget, args...) = exec(w.interp, w.path, args...)
exec(w::TkWidget, ::Type{T}, args...) where {T} = exec(T, w.interp, w.path, args...)
exec(::Type{T}, w::TkWidget, args...) where {T} = exec(T, w.interp, w.path, args...)

# We want to have the object type and path both printed in the REPL but want
# only the object path with the `string` method or for string interpolation.
# Note that: "$w" calls `string(w)` while "anything $w" calls `show(io, w)`.

function Base.show(io::IO, ::MIME"text/plain", w::T) where {T<:TkWidget}
    print(io, T, "(\"")
    write(io, w.path)
    print(io, "\")")
    return nothing
end

Base.show(io::IO, w::TkObject) = write(io, w.path)

"""
    tk_start(interp = TclInterp()) -> interp

If Tk package is not already loaded in the interpreter `interp`, load Tk and Ttk
packages in `interp` and start the event loop (for all interpreters).

If it is detected that Tk is already loaded in the interpreter, nothing is done.

!!! note
    `tk_start` also takes care of withdrawing the root window "." to avoid its destruction
    as this would terminate the Tcl application. Execute Tcl command `wm deiconify .` to
    show the root window again.

# See also

[`Tcl.resume`](@ref), [`TclInterp`](@ref), and [`TkWidget`](@ref).

"""
function tk_start(interp::TclInterp = TclInterp()) :: TclInterp
    if ! interp(Bool, "info exists tk_version")
        local status::TclStatus
        status = interp(TclStatus, "package require Tk")
        status == TCL_OK && (status = interp(TclStatus, "package require Ttk"))
        status == TCL_OK && (status = interp(TclStatus, "wm withdraw ."))
        status == TCL_OK || throw(TclError(interp))
        resume()
    end
    return interp
end

"""
    Tcl.configure(w)
    w(:configure)

Return all the options of Tk widget `w`.

---
    Tcl.configure(w, opt1 => val1, opt2 => val2)
    w(:configure, opt1 => val1, opt2 => val2)

Change some options of widget `w`. Options names (`opt1`, `opt2`, ...) may be specified as
string or `Symbol` and shall correspond to Tk option names without the leading "-". Another
way to change the settings is:

    w[opt1] = val1
    w[opt2] = val2

# See also

[`Tcl.cget`](@ref) and [`TkWidget`](@ref).

"""
configure(w::TkWidget, pairs...) = exec(w, :configure, pairs...)

"""
    Tcl.cget(w, opt)

Return the value of the option `opt` for widget `w`. Option `opt` may be specified as a
string or as a `Symbol` and shall corresponds to a Tk option name without the leading "-".
Another way to obtain an option value is:

    w[opt]

# See also

[`Tcl.configure`](@ref) and [`TkWidget`](@ref).

"""
cget(w::TkWidget, opt::Name) = exec(w, :cget, "-"*string(opt))
cget(::Type{T}, w::TkWidget, opt::Name) where {T} = exec(T, w, :cget, "-"*string(opt))
cget(w::TkWidget, ::Type{T}, opt::Name) where {T} = cget(T, w, opt)

Base.getindex(w::TkWidget, key::Name) = cget(w, key)
Base.getindex(w::TkWidget, (key,T)::Pair{<:Name,DataType}) = cget(T, w, key)
Base.getindex(w::TkWidget, ::Type{T}, key::Name) where {T} = cget(T, w, key)
Base.getindex(w::TkWidget, key::Name, ::Type{T}) where {T} = cget(T, w, key)
function Base.setindex!(w::TkWidget, value, key::Name)
    exec(w, :configure, key => value)
    return w
end

"""
    Tcl.grid(args...)
    Tcl.pack(args...)
    Tcl.place(args...)

Communicate with one of the Tk geometry manager. One of the arguments must be an instance of
`TkWidget`. For example:

```julia
using Tcl
tk_start()
top = TkToplevel()
Tcl.exec(:wm, :title, top, "A simple example")
btn = TkButton(top, :text => "Click me", :command => "puts \"ouch!\"")
Tcl.pack(btn, :side => :bottom, :padx => 30, :pady => 5)
```

The call to `Tcl.list` (could also be `Tcl.quote_string` here) is to avoid that the words in
the title be split as separate arguments.

"""
function grid end
@doc @doc(grid) pack
@doc @doc(grid) place

for cmd in (:grid, :pack, :place)
    @eval begin
        $cmd(args...) = $cmd(TclObj, args...)
        function $cmd(::Type{T}, args...) where {T}
            interp = common_interpreter(nothing, args...)
            interp == nothing && argument_error("missing a widget argument")
            return exec(T, interp, $(QuoteNode(cmd)), args...)
        end
    end
end

common_interpreter() = nothing
common_interpreter(interp::Union{Nothing,TclInterp}) = interp
common_interpreter(interp::Union{Nothing,TclInterp}, arg::Any, args...) =
    common_interpreter(interp, args...)
common_interpreter(::Nothing, arg::TkWidget, args...) =
    common_interpreter(arg.interp, args...)
function common_interpreter(interp::TclInterp, arg::TkWidget, args...)
    pointer(interp) == pointer(arg.interp) || argument_error("not all widgets have the same interpreter")
    return common_interpreter(interp, args...)
end

# Base.bind is overloaded because it already exists for sockets, but there
# should be no conflicts.
"""
    bind(w, ...)

Bind events to widget `w` or yields bindings for widget `w`.

With a single argument:

    bind(w)

yields bindings for widget `w`; while

    bind(w, seq)

yields the specific bindings for the sequence of events `seq` and

    bind(w, seq, script)

arranges to invoke `script` whenever any event of the sequence `seq` occurs for widget `w`.
For instance:

    bind(w, "<ButtonPress>", "+puts click")

To deal with class bindings, the Tcl interpreter may be provided (otherwise the shared
interpreter of the thread will be used):

    bind([interp,] classname, args...)

where `classname` is the name of the widget class (a string or a symbol).

"""
Base.bind(arg0::TkWidget, args...) = bind(TclInterp(arg0), arg0, args...)
Base.bind(arg0::Name, args...) = bind(TclInterp(), arg0, args...)
Base.bind(interp::TclInterp, args...) = exec(interp, :bind, args...)
