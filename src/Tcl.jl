__precompile__(true)

baremodule Tcl

# Only export symbols which are prefixed with `Tcl`, `TCL_`, `Tk`, `Ttk` or
# `TK_`, other "public" symbols will be available with the `Tcl.` prefix.
const __EXPORTS = (
    :TclError,
    :TclInterp,
    :TclObj,
    :TclObjList,
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
#   :@TkWidget,
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

# This baremodule has a special `eval` method available as `Tcl.eval`.
using Base
function eval end
function error end

if VERSION < v"0.6.0"
    # macro for raw strings (will be part of Julia 0.6, see PR #19900 at
    # https://github.com/JuliaLang/julia/pull/19900).
    export @raw_str
    macro raw_str(s); s; end
end

# Hide most implementation methods in a private module but make `Tcl` module
# available (using a relative path, in case `Tcl` is itself embedded in another
# module).
module Impl
#using ...Tcl # for public symbols
#import ...Tcl: TclInterp, TclInterpPtr, TclObj, TclObjPtr, TkImage, TclStatus
import ...Tcl

if isfile(joinpath(dirname(@__FILE__),"..","deps","deps.jl"))
    include("../deps/deps.jl")
else
    error("Tcl not properly installed.  Please run `Pkg.build(\"Tcl\")` to create file \"",joinpath(dirname(@__FILE__),"..","deps","deps.jl"),"\"")
end

include("types.jl")
include("macros.jl")
include("calls.jl")
include("basics.jl")
include("objects.jl")
include("lists.jl")
include("variables.jl")
include("widgets.jl")
include("dialogs.jl")
include("images.jl")

end

# Import public methods, types and constants.  These will be available as
# `Tcl.$name`.
import .Impl:
    Callback,
    WideInt,
    atomictype,
    cget,
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
    getinterp,
    getparent,
    getpath,
    getphotosize,
    getpixels,
    getresult,
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

#include("shortnames.jl")

end # module
