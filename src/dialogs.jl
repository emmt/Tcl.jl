#
# dialogs.jl -
#
# Wrappers for some Tk dialog widgets.
#

"""

```julia
Tcl.messagebox(interp=Tcl.getinterp(); parent="", title="", message="",
               detail="", icon="info", type="ok", default="", command="")
```

pops up a Tk message box dialog and returns the name of the selected button.
Tcl interpreter `interp` is used to run the dialog.  Available keywords are:

- Keyword `parent` specifies the window of the logical parent of the message box.
  The message box is displayed on top of its parent window.

- Keyword `title` specifies the title of the message box.  This option is
  ignored on Mac OS X, where platform guidelines forbid the use of a title on
  this kind of dialog.

- Keyword `message` specifies the message to display in this message box.  The
  default value is an empty string.

- Keyword `detail` specifies an auxiliary message to the main message.  The
  message detail will be presented beneath the main message and, where
  supported by the OS, in a less emphasized font than the main message.

- Keyword `icon` specifies an icon to display: `"error"`, `"info"`,
  `"question"` or `"warning"`.  By default, the `"info"` icon is displayed.

- Keyword `type` specifies which predefined set of buttons is displayed.
  The following values are possible:

  - `"abortretryignore"` to display three buttons whose symbolic names are
    `"abort"`, `"retry"` and `"ignore"`.

  - `"ok"` to display one button whose symbolic name is `"ok"`.

  - `"okcancel"` to display two buttons whose symbolic names are `"ok"` and
    `"cancel"`.

  - `"retrycancel"` to display two buttons whose symbolic names are `"retry"`
    and `"cancel"`.

  - `"yesno"` to display two buttons whose symbolic names are `"yes"` and
    `"no"`.

  - `"yesnocancel"` to display three buttons whose symbolic names are `"yes"`,
    `"no"` and `"cancel"`.

- Keyword `default` gives the name of the default button for this message
  window ( `"ok"`, `"cancel"`, and so on).  See keyword `type` for a list of
  the button names.  If this option is not specified, the first button in the
  dialog will be made the default.

- Keyword `command` specifies the prefix of a Tcl command to invoke when the
  user closes the dialog. The actual command consists of string followed by a
  space and the name of the button clicked by the user to close the dialog.
  This is only available on Mac OS X.

Example:

```julia
answer = Tcl.messagebox(message="Really quit?", icon="question", type="yesno",
                        detail="Select \"Yes\" to make the application exit")
if answer == "yes"
    quit()
elseif answer == "no"
    Tcl.messagebox(message="I know you like this application!",
                   type="ok")
end
```

See also [`Tcl.choosedirectory`](@ref), [`Tcl.getopenfile`](@ref) and
[`Tcl.getsavefile`](@ref).

"""
function messagebox(interp::TclInterp = getinterp();
                    parent::AbstractString = "",
                    title::AbstractString = "",
                    message::AbstractString = "",
                    detail::AbstractString = "",
                    icon::AbstractString = "",
                    type::AbstractString = "",
                    default::AbstractString = "",
                    command::AbstractString = "")
    # Make sure Tk is loaded.
    tkstart(interp)

    # Build-up command.
    cmd = list("tk_messageBox")
    _push_dialog_option!(cmd, "-parent",  parent)
    _push_dialog_option!(cmd, "-title",   title)
    _push_dialog_option!(cmd, "-message", message)
    _push_dialog_option!(cmd, "-detail",  detail)
    _push_dialog_option!(cmd, "-icon",    icon)
    _push_dialog_option!(cmd, "-type",    type)
    _push_dialog_option!(cmd, "-default", default)
    _push_dialog_option!(cmd, "-command", command)

    # Evaluate command and return the result as a string.
    interp(String, cmd)
end

"""


```julia
Tcl.choosedirectory(interp=Tcl.getinterp(); parent="", title="", message="",
                    initialdir="", mustexist=false, command="")
```

pops up a Tk dialog box for the user to select a directory and returns the
chosen directory name (an empty string if none).  Tcl interpreter `interp` is
used to run the dialog.  Available keywords are:

- Keyword `parent` specifies the window of the logical parent of the message box.
  The message box is displayed on top of its parent window.

- Keyword `title` specifies the title of the message box.  This option is
  ignored on Mac OS X, where platform guidelines forbid the use of a title on
  this kind of dialog.

- Keyword `message` specifies the message to display in this message box.  The
  default value is an empty string.  This is only available on Mac OS X.

- Keyword `initialdir` specifies that the directories in directory should be
  displayed when the dialog pops up.  If this parameter is not specified, the
  initial directory defaults to the current working directory on non-Windows
  systems and on Windows systems prior to Vista.  On Vista and later systems,
  the initial directory defaults to the last user-selected directory for the
  application. If the parameter specifies a relative path, the return value
  will convert the relative path to an absolute path.

- Keyword `mustexist` specifies whether the user may specify non-existent
  directories.  If this parameter is true, then the user may only select
  directories that already exist.

- Keyword `command` specifies the prefix of a Tcl command to invoke when the
  user closes the dialog. The actual command consists of string followed by a
  space and the name of the button clicked by the user to close the dialog.
  This is only available on Mac OS X.

See also [`Tcl.getopenfile`](@ref), [`Tcl.getsavefile`](@ref) and
[`Tcl.messagebox`](@ref).

"""
function choosedirectory(interp::TclInterp = getinterp();
                         parent::AbstractString = "",
                         title::AbstractString = "",
                         message::AbstractString = "",
                         initialdir::AbstractString = "",
                         mustexist::Bool = false,
                         command::AbstractString = "")
    # Make sure Tk is loaded.
    tkstart(interp)

    # Build-up command.
    cmd = list("tk_chooseDirectory")
    _push_dialog_option!(cmd, "-parent",     parent)
    _push_dialog_option!(cmd, "-title",      title)
    _push_dialog_option!(cmd, "-initialdir", initialdir)
    _push_dialog_option!(cmd, "-mustexist",  mustexist)
    if Sys.isapple()
        _push_dialog_option!(cmd, "-message", message)
        _push_dialog_option!(cmd, "-command", command)
    end

    # Evaluate command and return the result as a string.
    interp(String, cmd)
end


"""

```julia
Tcl.getopenfile(interp=getinterp(); parent="", title="", message="",
                initialdir="", initialfile="", multiple=false,
                defaultextension="", filetypes="", typevariable="",
                command="")
```

or

```julia
Tcl.getsavefile(interp=getinterp(); parent="", title="", message="",
                initialdir="", initialfile="", confirmoverwrite=true,
                defaultextension="", filetypes="", typevariable="",
                command="")
```

pops up a Tk dialog box for the user to to select a file to open or save and
returns the name of the chosen file (an empty string if none).  Tcl interpreter
`interp` is used to run the dialog.  The following keywords are available:

- Keyword `parent` specifies the path of the logical parent of the file dialog.
  The file dialog is displayed on top of its parent window.  On Mac OS X, this
  turns the file dialog into a sheet attached to the parent window.

- Keyword `title` specifies a string to display as the title of the dialog box.
  If this option is not specified, then a default title is displayed.

- Keyword `message` Specifies a message to include in the client area of the
  dialog.  This is only available on Mac OS X.

- Keyword `initialdir` specifies the directory in which the files should be
  displayed when the dialog pops up.  If this parameter is not specified, the
  initial directory defaults to the current working directory on non-Windows
  systems and on Windows systems prior to Vista.  On Vista and later systems,
  the initial directory defaults to the last user-selected directory for the
  application. If the parameter specifies a relative path, the return value
  will convert the relative path to an absolute path.

- Keyword `initialfile` specifies a filename to be displayed in the dialog when
  it pops up.

- Keyword `multiple` specifies whether the user can choose multiple files from
  the Open dialog.

- Keyword `confirmoverwrite` configures how the Save dialog reacts when the
  selected file already exists, and saving would overwrite it.  A true value
  requests a confirmation dialog be presented to the user.  A false value
  requests that the overwrite take place without confirmation.

- Keyword `defaultextension` specifies a string that will be appended to the
  filename if the user enters a filename without an extension.  The default
  value is the empty string, which means no extension will be appended to the
  filename in any case.  This option is ignored on Mac OS X, which does not
  require extensions to filenames, and the UNIX implementation guesses
  reasonable values for this from the `filetypes` option when this is not
  supplied.

- If a file types listbox exists in the file dialog on the particular platform,
  keyword `filetypes` gives the filetypes in this listbox.  When the user
  choose a filetype in the listbox, only the files of that type are listed.  If
  this option is unspecified, or if it is set to the empty list, or if the File
  types listbox is not supported by the particular platform then all files are
  listed regardless of their types.  See Tk manual for more details.

- Keyword `typevariable` specifies the name of a global Tcl variable used to
  preselect which filter is used from filterList when the dialog box is opened
  and is updated when the dialog box is closed, to the last selected
  filter. The variable is read once at the beginning to select the appropriate
  filter.  If the variable does not exist, or its value does not match any
  filter typename, or is empty ({}), the dialog box will revert to the default
  behavior of selecting the first filter in the list. If the dialog is
  canceled, the variable is not modified.

- Keyword `command` specifies the prefix of a Tcl command to invoke when the
  user closes the dialog after having selected an item.  This callback is not
  called if the user cancelled the dialog.  The actual command consists of the
  `command` string followed by a space and the value selected by the user in
  the dialog.  This is only available on Mac OS X.

See also [`Tcl.choosedirectory`](@ref) and [`Tcl.messagebox`](@ref).

"""
function getopenfile(interp::TclInterp = getinterp();
                     parent::AbstractString = "",
                     title::AbstractString = "",
                     message::AbstractString = "",
                     initialdir::AbstractString = "",
                     initialfile::AbstractString = "",
                     multiple::Bool = false,
                     defaultextension::AbstractString = "",
                     filetypes::AbstractString = "",
                     typevariable::AbstractString = "",
                     command::AbstractString = "")
    # Make sure Tk is loaded.
    tkstart(interp)

    # Build-up command.
    cmd = list("tk_getOpenFile", "-multiple", multiple)
    _push_dialog_option!(cmd, "-parent",           parent)
    _push_dialog_option!(cmd, "-title",            title)
    _push_dialog_option!(cmd, "-initialdir",       initialdir)
    _push_dialog_option!(cmd, "-initialfile",      initialfile)
    _push_dialog_option!(cmd, "-defaultextension", defaultextension)
    _push_dialog_option!(cmd, "-filetypes",        filetypes)
    _push_dialog_option!(cmd, "-typevariable",     typevariable)
    if Sys.isapple()
        _push_dialog_option!(cmd, "-message", message)
        _push_dialog_option!(cmd, "-command", command)
    end

    # Evaluate command and return the result as a string.
    interp(String, cmd)
end

function getsavefile(interp::TclInterp = getinterp();
                     parent::AbstractString = "",
                     title::AbstractString = "",
                     message::AbstractString = "",
                     initialdir::AbstractString = "",
                     initialfile::AbstractString = "",
                     confirmoverwrite::Bool = true,
                     defaultextension::AbstractString = "",
                     filetypes::AbstractString = "",
                     typevariable::AbstractString = "",
                     command::AbstractString = "")
    # Make sure Tk is loaded.
    tkstart(interp)

    # Build-up command.
    cmd = list("tk_getSaveFile", "-confirmoverwrite", confirmoverwrite)
    _push_dialog_option!(cmd, "-parent",           parent)
    _push_dialog_option!(cmd, "-title",            title)
    _push_dialog_option!(cmd, "-initialdir",       initialdir)
    _push_dialog_option!(cmd, "-initialfile",      initialfile)
    _push_dialog_option!(cmd, "-defaultextension", defaultextension)
    _push_dialog_option!(cmd, "-filetypes",        filetypes)
    _push_dialog_option!(cmd, "-typevariable",     typevariable)
    if Sys.isapple()
        _push_dialog_option!(cmd, "-message", message)
        _push_dialog_option!(cmd, "-command", command)
    end

    # Evaluate command and return the result as a string.
    interp(String, cmd)
end

@doc @doc(getopenfile) getsavefile

# Append a string-valued option (nothing if the value is an empty string).
_push_dialog_option!(cmd::TclObj{<:Vector}, opt::AbstractString, val::String) =
    length(val) > 0 && lappend!(cmd, opt, val)

# Append a boolean-valued option.
_push_dialog_option!(cmd::TclObj{<:Vector}, opt::AbstractString, val::Bool) =
    lappend!(cmd, opt, (val ? "true" : "false"))
