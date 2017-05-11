#VERSION >= v"0.4.0-dev+6521" && __precompile__(true)

module Tcl

if isfile(joinpath(dirname(@__FILE__),"..","deps","libs.jl"))
    include("../deps/libs.jl")
else
    error("Tcl not properly installed.  Please create and edit file \"../deps/libs.jl\"")
end

export
    @TkWidget,
    TclError,
    TclInterp,
    TclObj,
    TclObjList,
    TkObject,
    TkImage,
    TkWidget,
    TkRootWidget,
    TkButton,
    TkCanvas,
    TkCheckbutton,
    TkEntry,
    TkFrame,
    TkLabel,
    TkLabelframe,
    TkListbox,
    TkMenu,
    TkMenubutton,
    TkMessage,
    TkPanedwindow,
    TkRadiobutton,
    TkRoot,
    TkScale,
    TkScrollbar,
    TkSpinbox,
    TkText,
    TkToplevel,
    TkWidget,
    TtkButton,
    TtkCheckbutton,
    TtkCombobox,
    TtkEntry,
    TtkFrame,
    TtkLabel,
    TtkLabelframe,
    TtkMenubutton,
    TtkNotebook,
    TtkPanedwindow,
    TtkProgressbar,
    TtkRadiobutton,
    TtkScale,
    TtkScrollbar,
    TtkSeparator,
    TtkSizegrip,
    TtkSpinbox,
    TtkTreeview,
    TCL_OK,
    TCL_ERROR,
    TCL_RETURN,
    TCL_BREAK,
    TCL_CONTINUE,
    TCL_GLOBAL_ONLY,
    TCL_NAMESPACE_ONLY,
    TCL_APPEND_VALUE,
    TCL_LIST_ELEMENT,
    TCL_LEAVE_ERR_MSG,
    TCL_DONT_WAIT,
    TCL_WINDOW_EVENTS,
    TCL_FILE_EVENTS,
    TCL_TIMER_EVENTS,
    TCL_IDLE_EVENTS,
    TCL_ALL_EVENTS,
    TCL_NO_EVAL,
    TCL_EVAL_GLOBAL,
    TCL_EVAL_DIRECT,
    TCL_EVAL_INVOKE,
    TCL_CANCEL_UNWIND,
    TCL_EVAL_NOERR,
    tclerror,
    tcleval,
    tcltry,
    tkstart

if VERSION < v"0.6.0"
    # macro for raw strings (will be part of Julia 0.6, see PR #19900 at
    # https://github.com/JuliaLang/julia/pull/19900).
    export @raw_str
    macro raw_str(s); s; end
end

include("types.jl")
include("base.jl")
include("widgets.jl")
include("dialogs.jl")
include("images.jl")
include("shortnames.jl")

end # module
