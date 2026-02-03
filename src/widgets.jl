#
# widgets.jl -
#
# Implement Tk (and TTk) widgets
#

"""
    @TkWidget cls cmd pfx

Create widget class `cls` based on Tk command `cmd` and using prefix `pfx` for automatically
defined widget names. If `pfx` starts with a dot, a top-level widget class is assumed. For
now, `cmd` and `pfx` must be string literals.

"""
macro TkWidget(_cls, cmd, pfx)

    cls = esc(_cls)
    isa(cmd, String) || error("command must be a string literal")
    isa(pfx, String) || error("prefix must be a string literal")

    if first(pfx) == '.'
        # Root (top-level) widget.
        quote
            struct $cls <: TkRootWidget
                interp::TclInterp
                path::String
                obj::TclObj
                function $cls(interp::TclInterp, name::Name, pairs::Pair...)
                    # It is sufficient to ensure that Tk is loaded for root widgets because
                    # other widgets must have a parent.
                    tk_start(interp)
                    path = widget_path(name)
                    obj = create_widget(interp, $cmd, path, pairs...)
                    return new(interp, path, obj)
                end
            end

            # Register widget class.
            register_widget_class(widget_class_name($(string(_cls))), $cls)

            # Provide optional arguments.
            $cls(pairs::Pair...) = $cls(TclInterp(), pairs...)
            $cls(name::Name, pairs::Pair...) = $cls(TclInterp(), name, pairs...)
            $cls(interp::TclInterp, pairs::Pair...) = $cls(interp, autoname($pfx), pairs...)

            # Make the widget callable.
            (w::$cls)(args...; kwds...) = w.interp(w.path, args...; kwds...)

        end
    else
        # Other (top-level) widget.
        quote
            struct $cls <: TkWidget
                parent::TkWidget
                interp::TclInterp
                path::String
                obj::TclObj
                function $cls(parent::TkWidget, child::Name, pairs::Pair...)
                    interp = parent.interp
                    path = widget_path(parent, child)
                    obj = create_widget(interp, $cmd, path, pairs...)
                    return new(parent, interp, path, obj)
                end
            end

            # Register widget class.
            register_widget_class(widget_class_name($(string(_cls))), $cls)

            # Provide optional arguments.
            $cls(parent::Union{TkWidget,Name}, pairs::Pair...) =
                $cls(parent, autoname($pfx), pairs...)

            # Get widget for parent.
            $cls(parent::Name, child::Name, pairs::Pair...) =
                $cls(TkWidget(parent), child, pairs...)

            # Make the widget callable.
            (w::$cls)(args...; kwds...) = w.interp(w.path, args...; kwds...)
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

# Attempt to guess widget class name in Tk.
function widget_class_name(class::AbstractString)
    start, stop = firstindex(class), lastindex(class)
    if startswith(class, "Tk")
        index = nextind(class, start, 2)
        return String(SubString(class, index, stop))
    elseif startswith(class, "Ttk")
        index = nextind(class, start, 3)
        return String("T"*SubString(class, index, stop))
    else
        return String(class)
    end
    return nothing
end

# Top-level widgets.
@TkWidget TkToplevel      "::toplevel"          ".top"
@TkWidget TkMenu          "::menu"              ".mnu"

# Tk widgets.
@TkWidget TkButton        "::button"            "btn"
@TkWidget TkCanvas        "::canvas"            "cnv"
@TkWidget TkCheckbutton   "::checkbutton"       "cbt"
@TkWidget TkEntry         "::entry"             "ent"
@TkWidget TkFrame         "::frame"             "frm"
@TkWidget TkLabel         "::label"             "lab"
@TkWidget TkLabelframe    "::labelframe"        "lfr"
@TkWidget TkListbox       "::listbox"           "lbx"
@TkWidget TkMenubutton    "::menubutton"        "mbt"
@TkWidget TkMessage       "::message"           "msg"
@TkWidget TkPanedwindow   "::panedwindow"       "pwn"
@TkWidget TkRadiobutton   "::radiobutton"       "rbt"
@TkWidget TkScale         "::scale"             "scl"
@TkWidget TkScrollbar     "::scrollbar"         "sbr"
@TkWidget TkSpinbox       "::spinbox"           "sbx"
@TkWidget TkText          "::text"              "txt"

# Ttk (Themed Tk) widgets.
@TkWidget TtkButton       "::ttk::button"       "btn"
@TkWidget TtkCheckbutton  "::ttk::checkbutton"  "cbt"
@TkWidget TtkCombobox     "::ttk::combobox"     "cbx"
@TkWidget TtkEntry        "::ttk::entry"        "ent"
@TkWidget TtkFrame        "::ttk::frame"        "frm"
@TkWidget TtkLabel        "::ttk::label"        "lab"
@TkWidget TtkLabelframe   "::ttk::labelframe"   "lfr"
@TkWidget TtkMenubutton   "::ttk::menubutton"   "mbt"
@TkWidget TtkNotebook     "::ttk::notebook"     "nbk"
@TkWidget TtkPanedwindow  "::ttk::panedwindow"  "pwn"
@TkWidget TtkProgressbar  "::ttk::progressbar"  "pgb"
@TkWidget TtkRadiobutton  "::ttk::radiobutton"  "rbt"
@TkWidget TtkScale        "::ttk::scale"        "scl"
@TkWidget TtkScrollbar    "::ttk::scrollbar"    "sbr"
@TkWidget TtkSeparator    "::ttk::separator"    "sep"
@TkWidget TtkSizegrip     "::ttk::sizegrip"     "szg"
@TkWidget TtkSpinbox      "::ttk::spinbox"      "sbx"
@TkWidget TtkTreeview     "::ttk::treeview"     "trv"

register_widget_class("Tk", TkToplevel)

function TkWidget(path::Name, interp::TclInterp = TclInterp())
    isa(path, String) || (path = String(path))
    interp(Bool, "winfo exists", path) || argument_error(
        "\"$path\" is not the path of an existing widget")
    class = interp(String, "winfo class", path)
    # TODO for Tix: class = string(interp(path, "configure -class")[4])
    constructor = get(widget_classes, class, nothing)
    constructor == nothing && argument_error("widget \"$path\" has unknown class \"$class\"")
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
        # configuration options if any.  FIXME: there must be a way to check
        # the correctness of the widget class.
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
