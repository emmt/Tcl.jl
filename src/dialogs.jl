# Wrappers for some Tk dialog widgets.

"""

Example:

    answer = Tcl.messagebox(interp; message="Really quit?", icon="question",
        buttons="yesno", detail="Select \"Yes\" to make the application exit")
    if answer == "yes"
        quit()
    elseif answer == "no"
        Tcl.messagebox(interp; message="I know you like this application!",
            buttons="ok")
    end
"""
function messagebox(interp::TclInterp = getinterp();
                    default::String = NOTHING,
                    detail::String = NOTHING,
                    icon::String = NOTHING,
                    message::String = NOTHING,
                    title::String = NOTHING,
                    parent::String = NOTHING,
                    buttons::String = NOTHING)
    tkstart(interp)
    cmd = list("tk_messageBox")
    for (opt, val) in (("-default", default),
                       ("-detail", detail),
                       ("-icon", icon),
                       ("-message", message),
                       ("-parent", parent),
                       ("-title", title),
                       ("-type", buttons))
        if length(val) > 0
            lappend!(cmd, opt, val)
        end
    end
    interp(cmd)
end

function choosedirectory(interp::TclInterp = getinterp();
                         initialdir::String = NOTHING,
                         title::String = NOTHING,
                         parent::String = NOTHING,
                         mustexist::Bool = false)
    tkstart(interp)
    cmd = list("tk_chooseDirectory")
    for (opt, val) in (("-initialdir", initialdir),
                       ("-parent", parent),
                       ("-title", title))
        if length(val) > 0
            lappend!(cmd, opt, val)
        end
    end
    if mustexist
        lappend!(cmd, "-mustexist", "true")
    end
    interp(cmd)
end

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
function getopenfile(interp::TclInterp = getinterp();
                     defaultextension::String = NOTHING,
                     filetypes::String = NOTHING,
                     initialdir::String = NOTHING,
                     initialfile::String = NOTHING,
                     message::String = NOTHING,
                     multiple::Bool = false,
                     parent::String = NOTHING, # FIXME:
                     title::String = NOTHING,
                     typevariable::String = NOTHING)
    tkstart(interp)
    cmd = list("tk_getOpenFile", "-multiple", multiple)
    for (opt, val) in (("-defaultextension", defaultextension),
                       ("-filetypes", filetypes),
                       ("-initialdir", initialdir),
                       ("-initialfile", initialfile),
                       ("-parent", parent),
                       ("-title", title),
                       ("-typevariable", typevariable))
        if length(val) > 0
            lappend!(cmd, opt, val)
        end
    end
    if is_apple() && length(message) > 0
        lappend!(cmd, "-message", message)
    end
    interp(cmd)
end

function getsavefile(interp::TclInterp = getinterp();
                     confirmoverwrite::Bool = true,
                     defaultextension::String = NOTHING,
                     filetypes::String = NOTHING,
                     initialdir::String = NOTHING,
                     initialfile::String = NOTHING,
                     message::String = NOTHING,
                     parent::String = NOTHING, # FIXME:
                     title::String = NOTHING,
                     typevariable::String = NOTHING)
    tkstart(interp)
    cmd = list("tk_getSaveFile", "-confirmoverwrite", confirmoverwrite)
    for (opt, val) in (("-defaultextension", defaultextension),
                       ("-filetypes", filetypes),
                       ("-initialdir", initialdir),
                       ("-initialfile", initialfile),
                       ("-parent", parent),
                       ("-title", title),
                       ("-typevariable", typevariable))
        if length(val) > 0
            lappend!(cmd, opt, val)
        end
    end
    if is_apple() && length(message) > 0
        lappend!(cmd, "-message", message)
    end
    interp(cmd)
end
