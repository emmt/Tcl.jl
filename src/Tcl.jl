baremodule Tcl

# Tcl is a bare module because it implements its own `eval` function.
function eval end
using Base

# Non-exported public symbols.
using TypeUtils: @public
@public list concat eval exists setvar getvar unsetvar getresult setresult!

"""

`Tcl.Private` module hosts the private API of the `Tcl` package.

"""
module Private

import ..Tcl
using Tcl_jll
using Tk_jll
using CEnum
using Neutrals

if !isdefined(Base, :Memory)
    const Memory{T} = Vector{T}
end

include("glue.jl")
include("types.jl")
include("private.jl")
include("objects.jl")
include("lists.jl")
include("basics.jl")
include("variables.jl")
#include("callbacks.jl")
#include("widgets.jl")
#include("dialogs.jl")
#include("images.jl")

function __init__()
    # Many things do not work properly (e.g., freeing a Tcl object yields a segmentation
    # fault) if no interpreter has been created, so we always create an initial Tcl
    # interpreter for this thread.
    _ = TclInterp(:shared)

    # The table of known types is updated while objects of new types are created because
    # seeking for an existing type is much faster than creating the mutable TclObj
    # structure. Nevertheless, we know in advance that objects with NULL object type are
    # strings.
    unsafe_register_new_typename(ObjTypePtr(0))

    return nothing
end

end # module

# Public symbols. Only those with recognizable prefixes (like "Tcl", "TCL_", "Tk", etc.)
# are exported, the other must be explicitly imported or used with the `Tcl.` prefix.
for sym in (
    # Status.
    :TclStatus,
    :TCL_OK,
    :TCL_ERROR,
    :TCL_RETURN,
    :TCL_BREAK,
    :TCL_CONTINUE,

    # Events.
    :TCL_DONT_WAIT,
    :TCL_WINDOW_EVENTS,
    :TCL_FILE_EVENTS,
    :TCL_TIMER_EVENTS,
    :TCL_IDLE_EVENTS,
    :TCL_ALL_EVENTS,
    #:do_evants,
    #:do_one_event,
    #:isrunning,
    #:resume,
    #:suspend,

    # Variables.
    :TCL_GLOBAL_ONLY,
    :TCL_NAMESPACE_ONLY,
    :TCL_APPEND_VALUE,
    :TCL_LIST_ELEMENT,
    :TCL_LEAVE_ERR_MSG,
    :exists,
    :getvar,
    :setvar,
    :unsetvar,

    # Interpreters.
    :TclInterp,
    :getresult,
    :setresult!,

    # Types.
    #:Callback
    :TclObj,
    :TclError,
    :WideInt,

    # Scripts.
    #:eval,
    #:exec,

    # Lists.
    :concat,
    :list,

    # Others.
    :TclObj,
    :tcl_library,
    :tcl_version,

    # Tk.
    #:tkstart,
    #:@TkWidget,

    # Colors.
    :TkColor,
    :TkGray,
    :TkRGB,
    :TkBGR,
    :TkRGBA,
    :TkBGRA,
    :TkARGB,
    :TkABGR,

    # Widgets.
    #:TkObject,
    #:TkImage,
    #:TkWidget,
    #:TkRootWidget,
    #:TkButton,
    #:TkCanvas,
    #:TkCheckbutton,
    #:TkEntry,
    #:TkFrame,
    #:TkLabel,
    #:TkLabelframe,
    #:TkListbox,
    #:TkMenu,
    #:TkMenubutton,
    #:TkMessage,
    #:TkPanedwindow,
    #:TkRadiobutton,
    #:TkScale,
    #:TkScrollbar,
    #:TkSpinbox,
    #:TkText,
    #:TkToplevel,
    #:TkWidget,
    #:TtkButton,
    #:TtkCheckbutton,
    #:TtkCombobox,
    #:TtkEntry,
    #:TtkFrame,
    #:TtkLabel,
    #:TtkLabelframe,
    #:TtkMenubutton,
    #:TtkNotebook,
    #:TtkPanedwindow,
    #:TtkProgressbar,
    #:TtkRadiobutton,
    #:TtkScale,
    #:TtkScrollbar,
    #:TtkSeparator,
    #:TtkSizegrip,
    #:TtkSpinbox,
    #:TtkTreeview
    )

    # Import public symbols from the `Private` module, export those prefixed with `Tcl`,
    # `TCL_`, `Tk`, `@Tk`, `Ttk` or `TK_`, and declare the others as "public".
    @eval import .Private: $sym
    name = string(sym)
    if startswith(name, r"Tcl[A-Z]|TCL_|@?Tkk?[A-Z]")
        @eval export $sym
    end
end

#=
const __EXPORTS = (
    :TclObjCommand,
    :TCL_NO_EVAL,
    :TCL_EVAL_GLOBAL,
    :TCL_EVAL_DIRECT,
    :TCL_EVAL_INVOKE,
    :TCL_CANCEL_UNWIND,
    :TCL_EVAL_NOERR,
)

import .Impl:
    cget,
    choosecolor,
    choosedirectory,
    colorize!,
    colorize,
    configure,
    delete,
    deletecommand,
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
    messagebox,
    pack,
    place,
    setphotosize!,
    setpixels!,
    threshold!,

=#

end # module
