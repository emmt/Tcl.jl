#
# widgets.jl -
#
# Implement Tk (and TTk) widgets
#

"""
    @TkWidget cls cmd pfx

create widget class `cls` based on Tk command `cmd` and using prefix `pfx` for
automatically defined widget names.  If `pfx` starts with a dot, a toplevel
widget class is assumed.  For now, `cmd` and `pfx` must be string literals.

"""
macro TkWidget(_cls, cmd, pfx)

    cls = esc(_cls)
    isa(cmd, String) || error("command must be a string literal")
    isa(pfx, String) || error("prefix must be a string literal")

    pfx[1] == '.' ? quote

        struct $cls <: TkRootWidget
            interp::TclInterp
            path::String
            obj::TclObj{$cls}
            function $cls(interp::TclInterp, name::Name=autoname($pfx);
                          kwds...)
                # It is sufficient to ensure that Tk is loaded for root widgets
                # because other widgets must have a parent.
                tkstart(interp)
                path = __widgetpath(__string(name))
                obj = __createwidget($cls, interp, $cmd, path; kwds...)
                new(interp, path, obj)
            end
        end

        $cls(name::Name = autoname($pfx); kwds...) =
            $cls(getinterp(), name; kwds...)

        (w::$cls)(args...; kwds...) = Tcl.eval(w, args...; kwds...)

    end : quote

        struct $cls <: TkWidget
            parent::TkWidget
            interp::TclInterp
            path::String
            obj::TclObj{$cls}
            function $cls(parent::TkWidget, child::Name=autoname($pfx);
                          kwds...)
                interp = getinterp(parent)
                path = __widgetpath(parent, __string(child))
                obj = __createwidget($cls, interp, $cmd, path; kwds...)
                new(parent, interp, path, obj)
            end
        end

        (w::$cls)(args...; kwds...) = Tcl.eval(w, args...; kwds...)

    end
end

@TkWidget TkToplevel      "::toplevel"          ".top"
@TkWidget TkMenu          "::menu"              ".mnu"

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

# Private method called to check/build the path of a child widget.
function __widgetpath(parent::TkWidget, child::String) :: String
    if findfirst(isequal('.'), child) === nothing
        Tcl.error("illegal window name \"$(child)\"")
    end
    parentpath = getpath(parent)
    return (parentpath == "." ? "." : parentpath*".")*child
end

# Private method called to check the path of a root widget.
function __widgetpath(path::String) :: String
    if path[1] != '.'
        Tcl.error("root window name must start with a dot")
    end
    if findnext(isequal('.'), child, 2) === nothing
        Tcl.error("illegal root window name \"$(path)\"")
    end
    return path
end

# Private method called to create a widget.
function __createwidget(::Type{T}, interp::TclInterp,
                        cmd::String, path::String;
                        kwds...) where {T<:Union{TkWidget,TkRootWidget}}
    local objptr :: TclObjPtr
    if interp(Bool, "winfo exists", path)
        # If widget already exists, it will be simply re-used, so we just apply
        # configuration options if any.  FIXME: there must be a way to check
        # the correctness of the widget class.
        if length(kwds) > 0
            exec(path, "configure"; kwds...)
        end
        objptr = __newobj(path)
    else
        # Widget does not already exists, create it with configuration options.
        if exec(TclStatus, interp, cmd, path; kwds...) != TCL_OK
            Tcl.error(interp)
        end
        objptr = Tcl_GetObjResult(interp.ptr)
    end
    return TclObj{T}(objptr)
end

"""
    TkToplevel([interp], ".")

yields the toplevel Tk window for interpreter `interp` (or for the initial
interpreter if this argument is omitted).  This also takes care of loading Tk
extension in the interpreter and starting the event loop.

To create a new toplevel window:

    TkToplevel([interp,] path; kwds...)

""" TkToplevel

getinterp(w::TkWidget) = w.interp
getpath(w::TkWidget) = w.path
getparent(w::TkWidget) = w.parent
getparent(::TkRootWidget) = nothing
TclObj(w::TkWidget) = w.obj
AtomicType(::Type{<:TkWidget}) = Atomic()
__objptr(w::TkWidget) = __objptr(w.obj)

getpath(root::TkWidget, args::AbstractString...) =
    getpath(getpath(root), args...)

getpath(arg0::AbstractString, args::AbstractString...) =
   join(((arg0 == "." ? "" : arg0), args...), '.')

Tcl.eval(w::TkWidget, args...) =
    Tcl.eval(getinterp(w), w.obj, args...)

exec(w::TkWidget, args...; kwds...) =
    exec(getinterp(w), w.obj, args...; kwds...)

"""
If Tk package is not yet loaded in interpreter `interp` (or in the initial
interpreter if this argument is missing), then:

```julia
tkstart([interp]) -> interp
```

will load Tk package and start the event loop.  The returned value is the
interpreter into which Tk has been started.  Note that this method also takes
care of withdrawing the root window "." to avoid its destruction as this would
terminate the Tcl application.

"""
function tkstart(interp::TclInterp = getinterp()) :: TclInterp
    if ! interp(Bool, "info exists tk_version")
        local status::TclStatus
        status = interp(TclStatus, "package require Tk")
        status == TCL_OK && (status = interp(TclStatus, "package require Ttk"))
        status == TCL_OK && (status = interp(TclStatus, "wm withdraw ."))
        status == TCL_OK || Tcl.error(interp)
        resume()
    end
    return interp
end

"""
    Tcl.configure(w)

yields all the options of Tk widget `w`, while:

    Tcl.configure(w, opt1=val1, opt2=val2)

change some options of widget `w`.  Options names may be specified as `String`
or `Symbol`.  Another way to change the settings is:

    w[opt1] = val1
    w[opt2] = val2

"""
configure(w::TkWidget; kwds...) = exec(w, "configure"; kwds...)

"""

    Tcl.cget(w, opt)

yields the value of the option `opt` for widget `w`.  Option `opt` may be
specified as a `String` or as a `Symbol`.  Another way to obtain an option
value is:

    w[opt]

"""
cget(w::TkWidget, opt::Name) = exec(w, "cget", "-"*string(opt))

Base.getindex(w::TkWidget, key::Name) = cget(w, key)
Base.setindex!(w::TkWidget, value, key::Name) = begin
    exec(w, "configure", "-"*string(key), value)
    w
end

"""
    Tcl.grid(args...; kwds...)
    Tcl.pack(args...; kwds...)
    Tcl.place(args...; kwds...)

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
        function $cmd(args...; kwds...)
            for arg in args
                if isa(arg, TkWidget)
                    interp = getinterp(arg)
                    return exec(interp, $(string(cmd)), args...; kwds...)
                end
            end
            Tcl.error("missing a widget argument")
        end
    end
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
Base.bind(arg0::TkWidget, args...) = bind(getinterp(arg0), arg0, args...)
Base.bind(arg0::Name, args...) = bind(getinterp(), arg0, args...)
Base.bind(interp::TclInterp, args...) = exec(interp, "bind", args...)
