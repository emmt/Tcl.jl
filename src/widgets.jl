# Implement Tk (and TTk) widgets

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
            $cls(interp::TclInterp, name::Name=autoname($pfx); kwds...) =
                new(interp, __createwidget(interp, $cmd, name; kwds...))
        end

        $cls(name::Name = autoname($pfx); kwds...) =
            $cls(getinterp(), name; kwds...)

        (w::$cls)(args...; kwds...) = evaluate(w, args...; kwds...)

    end : quote

        struct $cls <: TkWidget
            parent::TkWidget
            interp::TclInterp
            path::String
            $cls(parent::TkWidget, child::Name=autoname($pfx); kwds...) =
                new(parent, getinterp(parent),
                    __createwidget(parent, $cmd, child; kwds...))
        end

        (w::$cls)(args...; kwds...) = evaluate(w, args...; kwds...)

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

# Private method called to create a child widget.
function __createwidget(parent::TkWidget, cmd::String, child::AbstractString;
                        kwds...)
    for c in child
        c == '.' && tclerror("illegal window name \"$(child)\"")
    end
    path = (getpath(parent) == "." ? "." : getpath(parent)*".")*child
    interp = getinterp(parent)
    if interp("winfo", "exists", path) != 0
        if length(kwds) > 0
            interp(path, "configure"; kwds...)
        end
    else
        interp(list(cmd, path; kwds...))
    end
    return path
end

__createwidget(parent::TkWidget, cmd::String, child::Symbol; kwds...) =
    __createwidget(parent, cmd, string(child); kwds...)

# Private method called to create a root widget.
function __createwidget(interp::TclInterp, cmd::String, path::AbstractString;
                        kwds...)
    path[1] == '.' || tclerror("root window name must start with a dot")
    @inbounds for i in 2:length(path)
        path[i] == '.' && tclerror("illegal root window name \"$(path)\"")
    end
    tkstart(interp)
    if interp("winfo", "exists", path) != 0
        if length(kwds) > 0
            interp(path, "configure"; kwds...)
        end
    else
        interp(list(cmd, path; kwds...))
    end
    return path
end

__createwidget(interp::TclInterp, cmd::String, path::Symbol; kwds...) =
    __createwidget(interp, cmd, string(path); kwds...)


@doc """
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
@inline TclObj(w::TkWidget) = TclObj{TkWidget}(__newobj(getpath(w)))

getpath(root::TkWidget, args::AbstractString...) =
    getpath(getpath(root), args...)

getpath(arg0::AbstractString, args::AbstractString...) =
   join(((arg0 == "." ? "" : arg0), args...), '.')

evaluate(w::TkWidget, args...; kwds...) =
    evaluate(getinterp(w), getpath(w), args...; kwds...)

"""
If Tk package is not yet loaded in interpreter `interp` (or in the initial
interpreter if this argument is missing), then:

    tkstart([interp]) -> interp

will load Tk package and start the event loop.  The returned value is the
interpreter into which Tk has been started.  Note that this method also takes
care of withdrawing the root window "." to avoid its destruction as this would
terminate the Tcl application.

"""
function tkstart(interp::TclInterp = getinterp()) :: TclInterp
    if interp("info","exists","tk_version") == 0
        code = tclcatch(interp, "package", "require", "Tk")
        if code == TCL_OK
            tclcatch(interp, "package", "require", "Ttk")
            code = tclcatch(interp, "wm", "withdraw", ".")
        end
        code == TCL_OK || tclerror(interp)
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
configure(w::TkWidget; kwds...) = evaluate(w, "configure"; kwds...)

"""

    Tcl.cget(w, opt)

yields the value of the option `opt` for widget `w`.  Option `opt` may be
specified as a `String` or as a `Symbol`.  Another way to obtain an option
value is:

    w[opt]

"""
cget(w::TkWidget, opt::Name) = evaluate(w, "cget", "-"*string(opt))

Base.getindex(w::TkWidget, key::Name) = cget(w, key)
Base.setindex!(w::TkWidget, value, key::Name) =
    evaluate(w, "configure", "-"*string(key), value)

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
                    return interp($(string(cmd)), args...; kwds...)
                end
            end
            tclerror("missing a widget argument")
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
Base.bind(arg0::Name, args...) = bind(getinterp(), "bind", arg0, args...)
Base.bind(interp::TclInterp, args...) = interp("bind", args...)
