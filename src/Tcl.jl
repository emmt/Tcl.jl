module Tcl

if isfile(joinpath(dirname(@__FILE__),"..","deps","libs.jl"))
    include("../deps/libs.jl")
else
    error("Tcl not properly installed.  Please create and edit file \"../deps/libs.jl\"")
end

export
    TclInterp,
    TclError,
    TclObj,
    TclObjList,
    TkWidget,
    TkRoot,
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
    TkScale,
    TkScrollbar,
    TkSpinbox,
    TkText,
    TkToplevel,
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
    tclerror

include("types.jl")
include("base.jl")
include("callbacks.jl")
include("widgets.jl")
include("dialogs.jl")
include("images.jl")

end # module
