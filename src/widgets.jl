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
                path::String
                obj::TclObj
                function $type(interp::TclInterp, name::Name, pairs::Pair...)
                    # It is sufficient to ensure that Tk is loaded for root widgets because
                    # other widgets must have a parent.
                    tk_start(interp)
                    path = widget_path(name)
                    obj = create_widget(interp, $command, path, pairs...)
                    return new(interp, path, obj)
                end
            end

            # Provide optional arguments.
            $type(pairs::Pair...) = $type(TclInterp(), pairs...)
            $type(name::Name, pairs::Pair...) = $type(TclInterp(), name, pairs...)
            $type(interp::TclInterp, pairs::Pair...) = $type(interp, autoname($prefix), pairs...)

            # Make the widget callable.
            (w::$type)(args...; kwds...) = w.interp(w.path, args...; kwds...)

            # Register widget class.
            register_widget_class($class, $type)
        end
    else
        # Other (top-level) widget.
        quote
            struct $type <: TkWidget
                parent::TkWidget
                interp::TclInterp
                path::String
                obj::TclObj
                function $type(parent::TkWidget, child::Name, pairs::Pair...)
                    interp = parent.interp
                    path = widget_path(parent, child)
                    obj = create_widget(interp, $command, path, pairs...)
                    return new(parent, interp, path, obj)
                end
            end

            # Provide optional arguments.
            $type(parent::Union{TkWidget,Name}, pairs::Pair...) =
                $type(parent, autoname($prefix), pairs...)

            # Get widget for parent.
            $type(parent::Name, child::Name, pairs::Pair...) =
                $type(TkWidget(parent), child, pairs...)

            # Make the widget callable.
            (w::$type)(args...; kwds...) = w.interp(w.path, args...; kwds...)

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

function TkWidget(path::Name, interp::TclInterp = TclInterp())
    isa(path, String) || (path = String(path))
    interp(Bool, "winfo exists", path) || argument_error(
        "\"$path\" is not the path of an existing widget")
    class = interp(String, "winfo class", path)
    # TODO for Tix widgets, we may instead use: class = string(interp(path, "configure -class")[4])
    constructor = get(widget_classes, class, nothing)
    constructor == nothing && argument_error(
        "widget \"$path\" has unregistered class \"$class\"")
    return constructor(interp, path)
end

# Private method called to check/build the path of a child widget.
function widget_path(parent::TkWidget, child::Union{AbstractString,Symbol})::String
    isa(child, Union{String,SubString{String}}) || (child = String(child))
    startswith(child, '.') && argument_error("window name \"$(child)\" must not start with a dot")
    parentpath = getpath(parent)
    return ((parentpath == "." ? "." : parentpath*".")*child)
end

# Private method called to check the path of a root widget.
function widget_path(path::Union{AbstractString,Symbol})::String
    isa(path, String) || (path = String(path))
    startswith(path, '.') || argument_error("root window name must start with a dot")
    findnext(isequal('.'), path, nextind(path, firstindex(path))) === nothing || argument_error(
        "illegal root window name \"$(path)\"")
    return path
end

# Private method called to create a widget.
function create_widget(interp::TclInterp, cmd::String, path::String, pairs::Pair...)::TclObj
    if interp(Bool, "winfo exists", path)
        # If widget already exists, it will be simply re-used, so we just apply
        # configuration options if any.
        if length(pairs) > 0
            status = interp(TclStatus, path, "configure", pairs...)
            status == TCL_OK || throw(TclError(interp))
        end
        return TclObj(path)
    else
        # Widget does not already exists, create it with configuration options.
        status = interp(TclStatus, cmd, path, pairs...)
        status == TCL_OK || throw(TclError(interp))
        return getresult(TclObj, interp)
    end
end

"""
    TkToplevel(interp=TclInterp(), ".")

Return the top-level Tk window for Tcl interpreter `interp`. This also takes care of loading
Tk extension in the interpreter and starting the event loop.

To create a new toplevel window:

    TkToplevel(interp, path, pairs...)

""" TkToplevel

TclInterp(w::TkWidget) = w.interp
getpath(w::TkWidget) = w.path
Base.parent(w::TkWidget) = w.parent
Base.parent(::TkRootWidget) = nothing
TclObj(w::TkWidget) = w.obj
Base.convert(::Type{TclObj}, w::TkWidget) = TclObj(w)::TclObj
get_objptr(w::TkWidget) = get_objptr(w.obj)

getpath(root::TkWidget, args::AbstractString...) =
    getpath(getpath(root), args...)

getpath(arg0::AbstractString, args::AbstractString...) =
   join(((arg0 == "." ? "" : arg0), args...), '.')

Tcl.eval(w::TkWidget, args...) = Tcl.eval(TclInterp(w), w.obj, args...)

# FIXME exec(w::TkWidget, args..., pairs...) =
# FIXME     exec(TclInterp(w), w.obj, args..., pairs...)

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

[`Tcl.resume`](@ref) and [`TclInterp`](@ref).

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

Return all the options of Tk widget `w`, while:

    Tcl.configure(w, opt1 => val1, opt2 => val2)

change some options of widget `w`. Options names (`opt1`, `opt2`, ...) may be specified as
string or `Symbol`. Another way to change the settings is:

    w[opt1] = val1
    w[opt2] = val2

"""
configure(w::TkWidget, pairs...) = Tcl.eval(w, "configure", pairs...)

"""

    Tcl.cget(w, opt)

Return the value of the option `opt` for widget `w`. Option `opt` may be specified as a
string or as a `Symbol`. Another way to obtain an option value is:

    w[opt]

"""
cget(w::TkWidget, opt::Name) = Tcl.eval(w, "cget", "-"*string(opt))

Base.getindex(w::TkWidget, key::Name) = cget(w, key)
function Base.setindex!(w::TkWidget, value, key::Name)
    Tcl.eval(w, "configure", "-"*string(key), value)
    return w
end

"""
    Tcl.grid(args..., pairs...)
    Tcl.pack(args..., pairs...)
    Tcl.place(args..., pairs...)

communicate with one of the Tk geometry manager.  One of the arguments must be
an instance of `TkWidget`.  For instance (assuming `top` is some frame or
toplevel widget):

    using Tcl
    Tcl.pack(TkButton(top, "b1"; text="Send message",
                      command = (args...) -> println("message sent!")),
             side = "bottom")

"""
function grid end
@doc @doc(grid) pack
@doc @doc(grid) place

for cmd in (:grid, :pack, :place)
    @eval begin
        function $cmd(args...)
            interp = common_interpreter(nothing, args...)
            interp == nothing && argument_error("missing a widget argument")
            return Tcl.eval(interp, $(string(cmd)), args...)
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

binds events to widget `w` or yields bindings for widget `w`.  With a single
argument

    bind(w)

yields binded sequences for widget `w`; while

    bind(w, seq)

yields the specific bindings for the sequence of events `seq` and

    bind(w, seq, script)

arranges to invoke `script` whenever any event of the sequence `seq` occurs for
widget `w`.  For instance:

    bind(w, "<ButtonPress>", "+puts click")

To deal with class bindings, the Tcl interpreter may be provided (otherwise the
initial interpreter will be used):

    bind([interp,] classname, args...)

where `classname` is the name of the widget class (a string or a symbol).

"""
Base.bind(arg0::TkWidget, args...) = bind(TclInterp(arg0), arg0, args...)
Base.bind(arg0::Name, args...) = bind(TclInterp(), arg0, args...)
Base.bind(interp::TclInterp, args...) = Tcl.eval(interp, "bind", args...)
