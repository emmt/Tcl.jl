import Tcl

module TclDemos

using Tcl
using Tcl.ShortNames

function addseedismiss(parent, child)
    #import Tcl: list
    ## See Code / Dismiss buttons
    interp = getinterp(parent)
    w = TFrame(parent, child)
    if isdefined(:TSeparator)
        sep = TSeparator(w, "sep")
    else
        sep = TFrame(w, "sep", height=2, relief="sunken")
    end
    grid(sep, columnspan=4, row=0, sticky="ew", pady="2")
    dismiss = TButton(w,"dismiss", text="Dismiss",
                        #image="::img::delete",
                        compound="left",
                        command=list("destroy",
                                     interp("winfo","toplevel",w)))

    # createcommand(interp, "jlcallback", (args...) -> println("Ouch!"))
    code = TButton(w, "code", text="See Code",
                     #image="::img::view",
                     compound = "left",
                     command = (args...) -> println("Ouch!"))
    buttons = (dismiss, code)

    #set buttons [list x $w.code $w.dismiss]
    #if {[llength $vars]} {
    #    TButton $w.vars -text [mc "See Variables"] \
    #        -image ::img::view -compound left \
    #        -command [concat [list showVars $w.dialog] $vars]
    #    set buttons [linsert $buttons 1 $w.vars]
    #}
    #if {$extra ne ""} {
    #    set buttons [linsert $buttons 1 [uplevel 1 $extra]]
    #}
    #grid {*}$buttons -padx 4 -pady 4
    #grid columnconfigure $w 0 -weight 1

    grid(buttons..., padx=4, pady=4)
    grid("columnconfigure", w, 0, weight=1)

    #if {[tk windowingsystem] eq "aqua"} {
    #    foreach b [lrange $buttons 1 end] {$b configure -takefocus 0}
    #    grid configure sep -pady 0
    #    grid configure {*}$buttons -pady {10 12}
    #    grid configure [lindex $buttons 1] -padx {16 4}
    #    grid configure [lindex $buttons end] -padx {4 18}
    #}
    return w
end

function labelframedemo()
    interp = tkstart()
    wname = ".labelframe"
    interp("catch {destroy $wname}")
    w = Toplevel(wname)
    interp("wm","title",w,"Labelframe Demonstration")
    interp("wm","iconname",w,"labelframe")

    # Some information
    msg = Label(w, "msg", #font="Helveltica",
                  wraplength="4i", justify="left",
                  text="Labelframes are used to group related widgets together.  The label may be either plain text or another widget.")
    pack(msg, side="top")

    ## See Code / Dismiss buttons
    btns = addseedismiss(w, "buttons")
    pack(btns, side="bottom", fill="x")

    # Demo area
    wf = Frame(w, "f")
    pack(wf, side="bottom", fill="both", expand=true)

    # A group of radiobuttons in a labelframe

    f = Labelframe(wf, "f", text="Value", padx=2, pady=2)
    grid(f, row=0, column=0, pady="2m", padx="2m")

    for value in 1:4
        pack(Radiobutton(f,"b$value", text="This is value $value",
                         variable="lfdummy", value=value),
             side="top", fill="x", pady=2)
    end

    # Using a label window to control a group of options.
    interp(raw"""
            proc lfEnableButtons {w} {
                foreach child [winfo children $w] {
                    if {$child == "$w.cb"} continue
                    if {$::lfdummy2} {
                        $child configure -state normal
                    } else {
                        $child configure -state disabled
                    }
                }
            }
        """)

    f2 = Labelframe(wf,"f2", pady=2, padx=2)
    f2_cb = Checkbutton(f2,"cb", text="Use this option.",
                        variable="lfdummy2",
                        command="lfEnableButtons $f2", padx=0)
    f2("configure",labelwidget=f2_cb)
    grid(f2, row=0, column=1, pady="2m", padx="2m")

    for t in 0:2
        pack(Checkbutton(f2,"b$t", text="Option$(t+1)"),
             side="top", fill="x", pady=2)
    end
    interp("lfEnableButtons", f2)

    grid("columnconfigure", wf, (0,1), weight=1)
end

function runtests2()
    interp = tkstart()
    if false
        name = interp("image create photo -file /home/eric/work/code/CImg/CImg-1.5.5/examples/img/lena.pgm")
        interp("pack [button .b -image $name]")
        d = Tcl.getpixels(interp, name, :red);
    else
        name = tcleval("image create photo -file /home/eric/work/code/CImg/CImg-1.5.5/examples/img/lena.pgm")
        tcleval("pack [button .b -image $name]")
        d = Tcl.getpixels(name, :red);
    end
    return d;
end

end
