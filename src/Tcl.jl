baremodule Tcl

# Tcl is a bare module because it implements its own `eval` function. But `using Base` and
# the `include` function are needed.
using Base
include(filename::AbstractString) = Base.include(Tcl, filename)

export
    # Status.
    TclStatus,
    TCL_OK,
    TCL_ERROR,
    TCL_RETURN,
    TCL_BREAK,
    TCL_CONTINUE,

    # Events.
    TCL_DONT_WAIT,
    TCL_ALL_EVENTS,

    # Variables.
    TCL_GLOBAL_ONLY,
    TCL_NAMESPACE_ONLY,
    TCL_APPEND_VALUE,
    TCL_LIST_ELEMENT,
    TCL_LEAVE_ERR_MSG,

    # Others.
    TclInterp,
    TclObj,
    tcl_library,
    tcl_version

# Direct calls to the functions of the Tcl/Tk C libraries.
include("glue.jl")
import .Glue:
    # Status.
    TclStatus,
    TCL_OK,
    TCL_ERROR,
    TCL_RETURN,
    TCL_BREAK,
    TCL_CONTINUE,

    # Events.
    TCL_DONT_WAIT,
    TCL_ALL_EVENTS,

    # Variables.
    TCL_GLOBAL_ONLY,
    TCL_NAMESPACE_ONLY,
    TCL_APPEND_VALUE,
    TCL_LIST_ELEMENT,
    TCL_LEAVE_ERR_MSG

const WideInt = Glue.Tcl_WideInt

using Neutrals

if !isdefined(Base, :Memory)
    const Memory{T} = Vector{T}
end

include("types.jl")
include("private.jl")
include("objects.jl")
include("lists.jl")
include("basics.jl")
#include("variables.jl")
#include("widgets.jl")
#include("dialogs.jl")
#include("images.jl")

#=
# Only export symbols which are prefixed with `Tcl`, `TCL_`, `Tk`, `Ttk` or
# `TK_`, other "public" symbols will be available with the `Tcl.` prefix.
const __EXPORTS = (
    :TclError,
    :TclInterp,
    :TclObj,
    :TclObjCommand,
    :TclStatus,
    :TCL_OK,
    :TCL_ERROR,
    :TCL_RETURN,
    :TCL_BREAK,
    :TCL_CONTINUE,
    :TCL_GLOBAL_ONLY,
    :TCL_NAMESPACE_ONLY,
    :TCL_APPEND_VALUE,
    :TCL_LIST_ELEMENT,
    :TCL_LEAVE_ERR_MSG,
    :TCL_DONT_WAIT,
    :TCL_WINDOW_EVENTS,
    :TCL_FILE_EVENTS,
    :TCL_TIMER_EVENTS,
    :TCL_IDLE_EVENTS,
    :TCL_ALL_EVENTS,
    :TCL_NO_EVAL,
    :TCL_EVAL_GLOBAL,
    :TCL_EVAL_DIRECT,
    :TCL_EVAL_INVOKE,
    :TCL_CANCEL_UNWIND,
    :TCL_EVAL_NOERR,
    :tkstart,
    #:@TkWidget,
    # Colors:
    :TkColor,
    :TkGray,
    :TkRGB,
    :TkBGR,
    :TkRGBA,
    :TkBGRA,
    :TkARGB,
    :TkABGR,
    # Widgets:
    :TkObject,
    :TkImage,
    :TkWidget,
    :TkRootWidget,
    :TkButton,
    :TkCanvas,
    :TkCheckbutton,
    :TkEntry,
    :TkFrame,
    :TkLabel,
    :TkLabelframe,
    :TkListbox,
    :TkMenu,
    :TkMenubutton,
    :TkMessage,
    :TkPanedwindow,
    :TkRadiobutton,
    :TkScale,
    :TkScrollbar,
    :TkSpinbox,
    :TkText,
    :TkToplevel,
    :TkWidget,
    :TtkButton,
    :TtkCheckbutton,
    :TtkCombobox,
    :TtkEntry,
    :TtkFrame,
    :TtkLabel,
    :TtkLabelframe,
    :TtkMenubutton,
    :TtkNotebook,
    :TtkPanedwindow,
    :TtkProgressbar,
    :TtkRadiobutton,
    :TtkScale,
    :TtkScrollbar,
    :TtkSeparator,
    :TtkSizegrip,
    :TtkSpinbox,
    :TtkTreeview)

# Hide most implementation methods in a private module but make `Tcl` module
# available (using a relative path, in case `Tcl` is itself embedded in another
# module).
module Impl
#using ...Tcl # for public symbols
#import ...Tcl: TclInterp, TclInterpPtr, TclObj, TclObjPtr, TkImage, TclStatus
import ...Tcl

using Printf

end

# Import public methods, types and constants.  These will be available as
# `Tcl.$name`.
import .Impl:
    Callback,
    WideInt,
    AtomicType,
    cget,
    choosecolor,
    choosedirectory,
    colorize!,
    colorize,
    concat,
    configure,
    delete,
    deletecommand,
    exec,
    exists,
    findphoto,
    getheight,
    getopenfile,
    getparent,
    getpath,
    getphotosize,
    getpixels,
    getresult,
    getsavefile,
    getvalue,
    getvar,
    getwidth,
    grid,
    isactive,
    isdeleted,
    lappend!,
    lindex,
    list,
    llength,
    messagebox,
    pack,
    place,
    resume,
    setphotosize!,
    setpixels!,
    setresult,
    setvar,
    suspend,
    threshold!,
    unsetvar

# Reexport prefixed public symbols.
for sym in __EXPORTS
    @eval begin
        import .Impl: $sym
        export $sym
    end
end
=#

function __init__()
    # Many things do not work properly (e.g., freeing a Tcl object yields a segmentation
    # fault) if no interpreter has been created, so we always create an initial Tcl
    # interpreter for this thread.
    _ = TclInterp(:shared)

    # The table of known types is updated while objects of new types are created because
    # seeking for an existing type is much faster than creating the mutable TclObj
    # structure. Nevertheless, we know in advance that objects with NULL object type are
    # strings.
    unsafe_register_new_typename(null(ObjTypePtr))

    return nothing
end

end # module
