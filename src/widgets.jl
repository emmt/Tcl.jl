# Implement Tk (and TTk) widgets

__counter = 0

function autoname(prefix::AbstractString="w")
    global __counter
    __counter += 1
    return prefix*tclrepr(__counter)
end

abstract TkWidget
abstract TkRoot <: TkWidget

tclrepr(w::TkWidget) = widgetpath(w)

const __knownwidgets = (
    (:TTkButton, false, "::ttk::button", "btn"),
    (:TTkCheckbutton, false, "::ttk::checkbutton", "cbt"),
    (:TTkCombobox, false, "::ttk::combobox", "cbx"),
    (:TTkEntry, false, "::ttk::entry", "ent"),
    (:TTkFrame, false, "::ttk::frame", "frm"),
    (:TTkLabel, false, "::ttk::label", "lab"),
    (:TTkLabelframe, false, "::ttk::labelframe", "lfr"),
    (:TTkMenubutton, false, "::ttk::menubutton", "mbt"),
    (:TTkNotebook, false, "::ttk::notebook", "nbk"),
    (:TTkPanedwindow, false, "::ttk::panedwindow", "pwn"),
    (:TTkProgressbar, false, "::ttk::progressbar", "pgb"),
    (:TTkRadiobutton, false, "::ttk::radiobutton", "rbt"),
    (:TTkScale, false, "::ttk::scale", "scl"),
    (:TTkScrollbar, false, "::ttk::scrollbar", "sbr"),
    (:TTkSeparator, false, "::ttk::separator", "sep"),
    (:TTkSizegrip, false, "::ttk::sizegrip", "szg"),
    (:TTkSpinbox, false, "::ttk::spinbox", "sbx"),
    (:TTkTreeview, false, "::ttk::treeview", "trv"),
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
                path::String
                $cls(parent::TkWidget, child::Name=autoname($pfx); kwds...) =
                    new(parent, __createwidget(parent, $cmd, child; kwds...))
            end

        end

        (w::$cls)(args...; kwds...) = evaluate(w, args...; kwds...)
    end
end

# Private method called to create a child widget.
function __createwidget(parent::TkWidget, cmd::String, child::Name; kwds...)
    name = tclrepr(child)
    for c in name
        c == '.' && tclerror("illegal window name \"$(name)\"")
    end
    path = (widgetpath(parent) == "." ? "." : widgetpath(parent)*".")*name
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

# Private method called to create a root widget.
function __createwidget(interp::TclInterp, cmd::String, root::Name; kwds...)
    path = tclrepr(root)
    path[1] == '.' || tclerror("root window name must start with a dot")
    @inbounds for i in 2:length(path)
        c == '.' && tclerror("illegal root window name \"$(path)\"")
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


@doc """
    TkToplevel([interp], ".")

yields the toplevel Tk window for interpreter `interp` (or for the global
interpreter if this argument is omitted).  This also takes care of loading
Tk extension in the interpreter and starting the event loop.

To create a new toplevel window:

    TkToplevel([interp,] path; kwds...)

""" TkToplevel

# tk_optionMenu tk_dialog tk_messageBox tk_getOpenFile tk_getSaveFile tk_chooseColor tk_chooseDirectory


interpreter(w::TkRoot) = w.interp
interpreter(w::TkWidget) = interpreter(parent(w))
widgetpath(w::TkWidget) = w.path
parent(w::TkWidget) = w.parent
parent(::TkRoot) = nothing

evaluate(w::TkWidget, args...; kwds...) =
    evaluate(interpreter(w), list(widgetpath(w), args...; kwds...))

configure(w::TkWidget; kwds...) = evaluate(w, "configure"; kwds...)

cget(w::TkWidget, opt::Name) = evaluate(w, "cget", "-"*tclrepr(opt))
