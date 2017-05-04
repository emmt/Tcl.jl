module Tcl

const libtcl = "/usr/lib/x86_64-linux-gnu/libtcl.so"
const libtk = "/usr/lib/x86_64-linux-gnu/libtk.so"

import Base: show, showerror, getindex, setindex!, haskey

# FIXME: I do not like the naming conventions adopted here.
export
    TclInterp,
    TclError,
    tcleval,
    tclsetvar,
    tclunsetvar,
    tclexists,
    tclgetvar,
    tclresume,
    tclsuspend,
    tcldoevents,
    tclresult,
    tclerror

const EMPTY = ""

# Codes returned by Tcl fucntions.
const TCL_OK       = convert(Cint, 0)
const TCL_ERROR    = convert(Cint, 1)
const TCL_RETURN   = convert(Cint, 2)
const TCL_BREAK    = convert(Cint, 3)
const TCL_CONTINUE = convert(Cint, 4)

# Flags for settings the result.
const TCL_VOLATILE = convert(Ptr{Void}, 1)
const TCL_STATIC   = convert(Ptr{Void}, 0)
const TCL_DYNAMIC  = convert(Ptr{Void}, 3)

# Flags for Tcl variables.
const TCL_GLOBAL_ONLY    = convert(Cint, 1)
const TCL_NAMESPACE_ONLY = convert(Cint, 2)
const TCL_APPEND_VALUE   = convert(Cint, 4)
const TCL_LIST_ELEMENT   = convert(Cint, 8)
const TCL_LEAVE_ERR_MSG  = convert(Cint, 0x200)

# Flags for Tcl processing events.  Set TCL_DONT_WAIT to not sleep: process
# only events that are ready at the time of the call.  Set TCL_ALL_EVENTS to
# process all kinds of events: equivalent to OR-ing together all of the above
# flags or specifying none of them.
const TCL_DONT_WAIT     = convert(Cint, 1<<1)
const TCL_WINDOW_EVENTS = convert(Cint, 1<<2) # Process window system events.
const TCL_FILE_EVENTS   = convert(Cint, 1<<3) # Process file events.
const TCL_TIMER_EVENTS  = convert(Cint, 1<<4) # Process timer events.
const TCL_IDLE_EVENTS   = convert(Cint, 1<<5) # Process idle callbacks.
const TCL_ALL_EVENTS    = ~TCL_DONT_WAIT      # Process all kinds of events.

# The following values control how blocks are combined into photo images when
# the alpha component of a pixel is not 255, a.k.a. the compositing rule.
const TK_PHOTO_COMPOSITE_OVERLAY = convert(Cint, 0)
const TK_PHOTO_COMPOSITE_SET     = convert(Cint, 1)

immutable TclError <: Exception
    msg::String
end

showerror(io::IO, e::TclError) = print(io, "Tcl/Tk error: ", e.msg)

tclerror(msg::String) = throw(TclError(msg))

"""

A new Tcl interpreter is created by the command:

    interp = TclInterp()

The resulting object can be used as a function to evaluate a Tcl script, for
instance:

    interp("set x 45")

which yields the result of the script (here the string "45").  The object can
also be used as an array to access global Tcl variables (the variable name can
be specified as a string or as a symbol):

    interp["x"]          # yields value of variable "x"
    interp[:tcl_version] # yields version of Tcl
    interp[:x] = 33      # set the value of "x" and yields its value (as a string)

The Tcl interpreter is initialized and will be deleted when object is no longer
in use.  If Tk has been propoerly installed, then:

    interp("package require Tk")

should load Tk extension and create the "." toplevel Tk window.

"""
type TclInterp
    ptr::Ptr{Void}
    function TclInterp()
        ptr = ccall((:Tcl_CreateInterp, libtcl), Ptr{Void}, ())
        if ptr == C_NULL
            tclerror("unable to create Tcl interpreter")
        end
        obj = new(ptr)
        finalizer(obj, obj -> ccall((:Tcl_DeleteInterp, libtcl), Void,
                                    (Ptr{Void},), obj.ptr))
        code = ccall((:Tcl_Init, libtcl), Cint, (Ptr{Void},), ptr)
        if code != TCL_OK
            tclerror("unable to initialize Tcl interpreter")
        end
        return obj
    end
end

(interp::TclInterp)(script::String) = tcleval(interp, script)

local tclinterp::TclInterp

# Processing Tcl/Tk events.  The function `tcldoevents` must be repeatedly
# called too process events when Tk is loaded.
local timer::Timer
local counter::Int = 0

function tclsuspend()
    global timer
    if isdefined(:timer) && isopen(timer)
        close(timer)
    end
end

function tclresume()
    global timer
    if ! (isdefined(:timer) && isopen(timer))
        timer = Timer(tcldoevents, 0.1, 0.01)
    end
end

tcldoevents(::Timer) = tcldoevents()

function tcldoevents(flags::Integer = TCL_DONT_WAIT | TCL_ALL_EVENTS)
    while ccall((:Tcl_DoOneEvent, libtcl), Cint, (Cint,), flags) != 0
    end
end

function requiretk(interp::TclInterp)
    tcleval(interp, "package require Tk")
    tclresume()
end

tclresult(interp::TclInterp) =
    unsafe_string(ccall((:Tcl_GetStringResult, libtcl),
                        Ptr{UInt8}, (Ptr{Void},), interp.ptr))

function tcleval(interp::TclInterp, script::String)
    code = ccall((:Tcl_Eval,libtcl), Cint, (Ptr{Void}, Ptr{UInt8}),
                 interp.ptr, script)
    result = tclresult(interp)
    if code != TCL_OK
        tclerror(result)
    end
    return result
end

tclsetvar(interp::TclInterp, name::Symbol, args...) =
    tclsetvar(interp, string(name), args...)

tclsetvar(interp::TclInterp, name::String, value::Real, args...) =
    tclsetvar(interp, name, string(value), args...)

function tclsetvar(interp::TclInterp, name::String, value::String,
                   flags::Integer = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
    ptr = ccall((:Tcl_SetVar, libtcl), Ptr{UInt8},
                (Ptr{Void}, Ptr{UInt8}, Ptr{UInt8}, Cint),
                interp.ptr, name, value, flags)
    if ptr == C_NULL
        tclerror(tclresult(interp))
    end
    unsafe_string(ptr)
end

tclunsetvar(interp::TclInterp, name::Symbol, args...) =
    tclunsetvar(interp, string(name), args...)

function tclunsetvar(interp::TclInterp, name::String,
                     flags::Integer = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
    code = ccall((:Tcl_UnsetSetVar, libtcl), Cint,
                (Ptr{Void}, Ptr{UInt8}, Cint),
                 interp.ptr, name, flags)
    if code != TCL_OK
        tclerror(tclresult(interp))
    end
end

tclgetvar(interp::TclInterp, name::Symbol, args...) =
    tclgetvar(interp, string(name), args...)

function tclgetvar(interp::TclInterp, name::String,
                   flags::Integer = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
    ptr = ccall((:Tcl_GetVar, libtcl), Ptr{UInt8},
                (Ptr{Void}, Ptr{UInt8}, Cint),
                interp.ptr, name, flags)
    if ptr == C_NULL
        tclerror(tclresult(interp))
    end
    unsafe_string(ptr)
end

tclexists(interp::TclInterp, name::Symbol,args...) =
    tclexists(interp, string(name), args...)

function tclexists(interp::TclInterp, name::String,
                   flags::Integer = TCL_GLOBAL_ONLY|TCL_LEAVE_ERR_MSG)
    ccall((:Tcl_GetVar, libtcl), Ptr{UInt8}, (Ptr{Void}, Ptr{UInt8}, Cint),
          interp.ptr, key, TCL_GLOBAL_ONLY) != C_NULL
end

# Manage to make any Tcl interpreter usable as a collection with respect to its
# global variables.

getindex(interp::TclInterp, key) = tclgetvar(interp, key)
setindex!(interp::TclInterp, value, key) = tclsetvar(interp, key, value)
haskey(interp::TclInterp, key) = tclexists(interp, key)


# Wrappers for some Tk dialog widgets.

protect(str::String) = "{"*str*"}" # FIXME: Improve this.

function choosedirectory(interp::TclInterp;
                         initialdir::String=EMPTY,
                         title::String=EMPTY,
                         parent::String=EMPTY,
                         mustexist::Bool=false)
    requiretk(interp)
    script = "tk_chooseDirectory"
    for (opt, val) in ((" -initialdir ", initialdir),
                       (" -parent ", parent),
                       (" -title ", title))
        if length(val) > 0
            script *= opt*protect(val)
        end
    end
    if mustexist
        script *= " -mustexist true"
    end
    tcleval(interp, script)
end

include("photo.jl")

"""

## Keywords:

- `confirmoverwrite` Configures how the Save dialog reacts when the
  selected file already exists, and saving would overwrite it.  A true value
  requests a confirmation dialog be presented to the user.  A false value
  requests that the overwrite take place without confirmation.  Default value
  is true.

- `defaultextension` Specifies a string that will be appended to the filename
  if the user enters a filename without an extension. The default value is the
  empty string, which means no extension will be appended to the filename in
  any case. This option is ignored on Mac OS X, which does not require
  extensions to filenames, and the UNIX implementation guesses reasonable
  values for this from the `filetypes` option when this is not supplied.

- `filetypes` If a File types listbox exists in the file dialog on the
  particular platform, this option gives the filetypes in this listbox.  When
  the user choose a filetype in the listbox, only the files of that type are
  listed. If this option is unspecified, or if it is set to the empty list, or
  if the File types listbox is not supported by the particular platform then
  all files are listed regardless of their types.  See the section SPECIFYING
  FILE PATTERNS below for a discussion on the contents of filePatternList.

- `initialdir` Specifies that the files in directory should be displayed when
  the dialog pops up. If this parameter is not specified, the initial direc‐
  tory defaults to the current working directory on non-Windows systems and on
  Windows systems prior to Vista.  On Vista and later systems, the initial
  directory defaults to the last user-selected directory for the
  application. If the parameter specifies a relative path, the return value
  will convert the relative path to an absolute path.

- `initialfile` Specifies a filename to be displayed in the dialog when it pops
  up.

- `message` Specifies a message to include in the client area of the dialog.
  This is only available on Mac OS X.

- `multiple` Allows the user to choose multiple files from the Open dialog.

- `parent` Makes window the logical parent of the file dialog. The file dialog
  is displayed on top of its parent window. On Mac OS X, this turns the file
  dialog into a sheet attached to the parent window.

- `title` Specifies a string to display as the title of the dialog box. If this
  option is not specified, then a default title is displayed.

- `typevariable` The global variable variableName is used to preselect which
  filter is used from filterList when the dialog box is opened and is updated
  when the dialog box is closed, to the last selected filter. The variable is
  read once at the beginning to select the appropriate filter.  If the variable
  does not exist, or its value does not match any filter typename, or is empty
  ({}), the dialog box will revert to the default behavior of selecting the
  first filter in the list. If the dialog is canceled, the variable is not
  modified.

"""
function getopenfile(interp::TclInterp;
                     defaultextension::String = EMPTY,
                     filetypes::String = EMPTY,
                     initialdir::String = EMPTY,
                     initialfile::String = EMPTY,
                     message::String = EMPTY,
                     multiple::Bool = false,
                     parent::String = EMPTY, # FIXME:
                     title::String = EMPTY,
                     typevariable::String = EMPTY)
    requiretk(interp)
    script = "tk_getOpenFile -multiple "*string(multiple)
    for (opt, val) in ((" -defaultextension ", defaultextension),
                       (" -filetypes ", filetypes),
                       (" -initialdir ", initialdir),
                       (" -initialfile ", initialfile),
                       (" -parent ", parent),
                       (" -title ", title),
                       (" -typevariable ", typevariable))
        if length(val) > 0
            script *= opt*protect(val)
        end
    end
    if is_apple() && length(message) > 0
        script *= " -message "*protect(message)
    end
    tcleval(interp, script)
end

function getsavefile(interp::TclInterp;
                     confirmoverwrite::Bool = true,
                     defaultextension::String = EMPTY,
                     filetypes::String = EMPTY,
                     initialdir::String = EMPTY,
                     initialfile::String = EMPTY,
                     message::String = EMPTY,
                     parent::String = EMPTY, # FIXME:
                     title::String = EMPTY,
                     typevariable::String = EMPTY)
    requiretk(interp)
    script = "tk_getSaveFile -confirmoverwrite "*string(confirmoverwrite)
    for (opt, val) in ((" -defaultextension ", defaultextension),
                       (" -filetypes ", filetypes),
                       (" -initialdir ", initialdir),
                       (" -initialfile ", initialfile),
                       (" -parent ", parent),
                       (" -title ", title),
                       (" -typevariable ", typevariable))
        if length(val) > 0
            script *= opt*protect(val)
        end
    end
    if is_apple() && length(message) > 0
        script *= " -message "*protect(message)
    end
    tcleval(interp, script)
end

end # module
