# Define shortcuts for Tcl/Tk methods.
#
# Usage:
#
#     using Tcl
#     using Tcl.ShortNames
#

module ShortNames

using Tcl

export
    cget,
    configure,
    createcommand,
    #evaluate,
    getinterp,
    getparent,
    getpath,
    grid,
    list,
    pack,
    place,

    Button,
    Canvas,
    Checkbutton,
    Entry,
    Frame,
    Label,
    Labelframe,
    Listbox,
    Menu,
    Menubutton,
    Message,
    Panedwindow,
    Radiobutton,
    Scale,
    Scrollbar,
    Spinbox,
    TButton,
    TCheckbutton,
    TCombobox,
    TEntry,
    TFrame,
    TLabel,
    TLabelframe,
    TMenubutton,
    TNotebook,
    TPanedwindow,
    TProgressbar,
    TRadiobutton,
    TScale,
    TScrollbar,
    TSeparator,
    TSizegrip,
    TSpinbox,
    Text,
    Toplevel,
    Treeview

const cget          = Tcl.cget
const configure     = Tcl.configure
const createcommand = Tcl.createcommand
#const evaluate      = Tcl.evaluate  # FIXME: we already have `tcleval`
const getinterp     = Tcl.getinterp
const getparent     = Tcl.getparent
const getpath       = Tcl.getpath
const grid          = Tcl.grid
const list          = Tcl.list
const pack          = Tcl.pack
const place         = Tcl.place

# Use the same short names as the Tk class names given by `winfo class $w`.
const Button        = TkButton
const Canvas        = TkCanvas
const Checkbutton   = TkCheckbutton
const Entry         = TkEntry
const Frame         = TkFrame
const Label         = TkLabel
const Labelframe    = TkLabelframe
const Listbox       = TkListbox
const Menu          = TkMenu
const Menubutton    = TkMenubutton
const Message       = TkMessage
const Panedwindow   = TkPanedwindow
const Radiobutton   = TkRadiobutton
const Scale         = TkScale
const Scrollbar     = TkScrollbar
const Spinbox       = TkSpinbox
const TButton       = TtkButton
const TCheckbutton  = TtkCheckbutton
const TCombobox     = TtkCombobox
const TEntry        = TtkEntry
const TFrame        = TtkFrame
const TLabel        = TtkLabel
const TLabelframe   = TtkLabelframe
const TMenubutton   = TtkMenubutton
const TNotebook     = TtkNotebook
const TPanedwindow  = TtkPanedwindow
const TProgressbar  = TtkProgressbar
const TRadiobutton  = TtkRadiobutton
const TScale        = TtkScale
const TScrollbar    = TtkScrollbar
const TSeparator    = TtkSeparator
const TSizegrip     = TtkSizegrip
const TSpinbox      = TtkSpinbox
const Text          = TkText
const Toplevel      = TkToplevel
const Treeview      = TtkTreeview

end #module
