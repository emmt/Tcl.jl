baremodule Tcl

# Tcl is a bare module because it implements its own `eval` function.
function eval end
using Base

"""

`Tcl.Private` module hosts the private API of the `Tcl` package.

"""
module Private

import ..Tcl
using CEnum
using Neutrals

if !isdefined(Base, :Memory)
    const Memory{T} = Vector{T}
end
if !isdefined(Base, :isnothing)
    isnothing(::Any) = false
    isnothing(::Nothing) = true
end

include(joinpath("..", "deps", "deps.jl"))
include("libtcl.jl")
include("libtk.jl")
include("types.jl")
include("utils.jl")
include("objects.jl")
include("lists.jl")
include("interpreters.jl")
include("variables.jl")
include("callbacks.jl")
include("events.jl")
include("widgets.jl")
#include("dialogs.jl")
#include("images.jl")

function __init__()
    # Many things do not work properly (segmentation fault when freeing a Tcl object,
    # initialization of Tcl interpreters, etc.) if Tcl internals (encodings, sub-systems,
    # etc.) are not properly initialized. This is done by the following call.
    @ccall libtcl.Tcl_FindExecutable(joinpath(Sys.BINDIR, "julia")::Cstring)::Cvoid

    # The table of known types is updated while objects of new types are created because
    # seeking for an existing type is much faster than creating the mutable TclObj
    # structure. Nevertheless, we know in advance that objects with NULL object type are
    # strings.
    unsafe_register_new_typename(ObjTypePtr(0))

    # Compile C functions for callbacks.
    release_object_proc[] = @cfunction(unsafe_release, Cvoid, (Ptr{Cvoid},))
    eval_command_proc[] = @cfunction(eval_command, TclStatus,
                                     (ClientData, Ptr{Tcl_Interp},
                                      Cint, Ptr{Ptr{Tcl_Obj}}))
    return nothing
end

end # module

# Public symbols. Only those with recognizable prefixes (like "Tcl", "TCL_", "Tk", etc.)
# are exported, the other must be explicitly imported or used with the `Tcl.` prefix.
for sym in (
    # Types.
    :Callback,
    :TclError,
    :TclInterp,
    :TclObj,
    :TclStatus,
    :WideInt,

    # Tk colors.
    :TkColor,
    :TkGray,
    :TkRGB,
    :TkBGR,
    :TkRGBA,
    :TkBGRA,
    :TkARGB,
    :TkABGR,

    # Version.
    :TCL_VERSION,
    :TCL_MAJOR_VERSION,
    :TCL_MINOR_VERSION,

    # Status constants.
    :TCL_OK,
    :TCL_ERROR,
    :TCL_RETURN,
    :TCL_BREAK,
    :TCL_CONTINUE,

    # Constants for events.
    :TCL_DONT_WAIT,
    :TCL_WINDOW_EVENTS,
    :TCL_FILE_EVENTS,
    :TCL_TIMER_EVENTS,
    :TCL_IDLE_EVENTS,
    :TCL_ALL_EVENTS,

    # Constants for variables.
    :TCL_GLOBAL_ONLY,
    :TCL_NAMESPACE_ONLY,
    :TCL_APPEND_VALUE,
    :TCL_LIST_ELEMENT,
    :TCL_LEAVE_ERR_MSG,

    # Methods.
    :cget,
    :concat,
    :configure,
    :deletecommand,
    :do_events,
    :do_one_event,
    :eval,
    :exec,
    :exists,
    :getresult,
    :getvar,
    :grid,
    :isrunning,
    :list,
    :pack,
    :place,
    :quote_string,
    :resume,
    :setresult!,
    :setvar,
    :suspend,
    :tcl_library,
    :tcl_version,
    :tk_start,
    :unsetvar,

    # Other Tk types.
    #:TkImage,
    :TkObject,
    :TkRootWidget,
    :TkWidget,

    # Tk widgets.
    Symbol("@TkWidget"),
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

    # Ttk (Themed Tk) widgets.
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
    :TtkTreeview
    )

    # Import public symbols from the `Private` module, export those prefixed with `Tcl`,
    # `TCL_`, `Tk`, `@Tk`, `Ttk` or `TK_`, and declare the others as "public".
    if sym != :eval
        @eval import .Private: $sym
    end
    name = string(sym)
    if startswith(name, r"@?(Tcl|tcl_|TCL_|Tt?k|tk_)")
        @eval export $sym
    elseif VERSION ≥ v"1.11.0-DEV.469"
        @eval $(Base.Expr(:public, sym))
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
    choosecolor,
    choosedirectory,
    colorize!,
    colorize,
    delete,
    findphoto,
    getheight,
    getopenfile,
    getparent,
    getpath,
    getphotosize,
    getpixels,
    getsavefile,
    getvalue,
    getvar,
    getwidth,
    isactive,
    isdeleted,
    messagebox,
    setphotosize!,
    setpixels!,
    threshold!,

=#

end # module
