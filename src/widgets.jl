# Implement Tk (and TTk) widgets

abstract TkWidget
abstract TkRoot <: TkWidget

Base.show{T<:TkWidget}(io::IO, w::T) =
    print(io, "$T(\"$(widgetpath(w))\")")

const __knownwidgets = (
    (:TtkButton, false, "::ttk::button", "btn"),
    (:TtkCheckbutton, false, "::ttk::checkbutton", "cbt"),
    (:TtkCombobox, false, "::ttk::combobox", "cbx"),
    (:TtkEntry, false, "::ttk::entry", "ent"),
    (:TtkFrame, false, "::ttk::frame", "frm"),
    (:TtkLabel, false, "::ttk::label", "lab"),
    (:TtkLabelframe, false, "::ttk::labelframe", "lfr"),
    (:TtkMenubutton, false, "::ttk::menubutton", "mbt"),
    (:TtkNotebook, false, "::ttk::notebook", "nbk"),
    (:TtkPanedwindow, false, "::ttk::panedwindow", "pwn"),
    (:TtkProgressbar, false, "::ttk::progressbar", "pgb"),
    (:TtkRadiobutton, false, "::ttk::radiobutton", "rbt"),
    (:TtkScale, false, "::ttk::scale", "scl"),
    (:TtkScrollbar, false, "::ttk::scrollbar", "sbr"),
    (:TtkSeparator, false, "::ttk::separator", "sep"),
    (:TtkSizegrip, false, "::ttk::sizegrip", "szg"),
    (:TtkSpinbox, false, "::ttk::spinbox", "sbx"),
    (:TtkTreeview, false, "::ttk::treeview", "trv"),
    (:TkButton, false, "::button", "btn"),
    (:TkCanvas, false, "::canvas", "cnv"),
    (:TkCheckbutton, false, "::checkbutton", "cbt"),
    (:TkEntry, false, "::entry", "ent"),
    (:TkFrame, false, "::frame", "frm"),
    (:TkLabel, false, "::label", "lab"),
    (:TkLabelframe, false, "::labelframe", "lfr"),
    (:TkListbox, false, "::listbox", "lbx"),
    (:TkMenu, true, "::menu", ".mnu"),
    (:TkMenubutton, false, "::menubutton", "mbt"),
    (:TkMessage, false, "::message", "msg"),
    (:TkPanedwindow, false, "::panedwindow", "pwn"),
    (:TkRadiobutton, false, "::radiobutton", "rbt"),
    (:TkScale, false, "::scale", "scl"),
    (:TkScrollbar, false, "::scrollbar", "sbr"),
    (:TkSpinbox, false, "::spinbox", "sbx"),
    (:TkText, false, "::text", "txt"),
    (:TkToplevel, true, "::toplevel", ".top"))

for (cls, top, cmd, pfx) in __knownwidgets
    @eval begin
        if $top

            immutable $cls <: TkRoot
                interp::TclInterp
                path::String
                $cls(interp::TclInterp, name::Name=autoname($pfx); kwds...) =
                    new(interp, __createwidget(interp, $cmd, name; kwds...))
            end

            $cls(name::Name = autoname($pfx); kwds...) =
                $cls(defaultinterpreter(), name; kwds...)

        else

            immutable $cls <: TkWidget
                parent::TkWidget
                interp::TclInterp
                path::String
                $cls(parent::TkWidget, child::Name=autoname($pfx); kwds...) =
                    new(parent, interpreter(parent),
                        __createwidget(parent, $cmd, child; kwds...))
            end

        end

        (w::$cls)(args...; kwds...) = evaluate(w, args...; kwds...)
    end
end

# Private method called to create a child widget.
function __createwidget(parent::TkWidget, cmd::String, child::AbstractString;
                        kwds...)
    for c in child
        c == '.' && tclerror("illegal window name \"$(child)\"")
    end
    path = (widgetpath(parent) == "." ? "." : widgetpath(parent)*".")*child
    interp = interpreter(parent)
    if parse(Int, interp("winfo", "exists", path)) != 0
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
    if parse(Int, interp("info exists tk_version")) == 0
        interp("package require Tk")
        resume()
    end
    if parse(Int, interp("winfo", "exists", path)) != 0
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

yields the toplevel Tk window for interpreter `interp` (or for the global
interpreter if this argument is omitted).  This also takes care of loading
Tk extension in the interpreter and starting the event loop.

To create a new toplevel window:

    TkToplevel([interp,] path; kwds...)

""" TkToplevel

# tk_optionMenu tk_dialog tk_messageBox tk_getOpenFile tk_getSaveFile tk_chooseColor tk_chooseDirectory


interpreter(w::TkWidget) = w.interp
widgetpath(w::TkWidget) = w.path
parent(w::TkWidget) = w.parent
parent(::TkRoot) = nothing
Base.string(w::TkWidget) = widgetpath(w)
@inline TclObj(w::TkWidget) =
    TclObj{TkWidget}(ccall((:Tcl_NewStringObj, libtcl), TclObjPtr,
                           (Ptr{UInt8}, Cint),
                           widgetpath(w), sizeof(widgetpath(w))))

evaluate(w::TkWidget, args...; kwds...) =
    evaluate(interpreter(w), list(widgetpath(w), args...; kwds...))

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

communicate with one of the Tk geometry manager.  One of the arguments must
be an instance of `TkWidget`.

"""
function grid end
@doc @doc(grid) pack
@doc @doc(grid) place

for cmd in (:grid, :pack, :place)
    @eval begin
        function $cmd(args...; kwds...)
            for arg in args
                if isa(arg, TkWidget)
                    interp = interpreter(arg)
                    return interp($(string(cmd)), args...; kwds...)
                end
            end
            tclerror("missing a widget argument")
        end
    end
end
