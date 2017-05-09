import Tcl

module TclDialogTests

using Tcl

function runtests()
    interp = Tcl.TclInterp()
    answer = Tcl.messagebox(interp; message="Really quit?", icon="question",
        buttons="yesno", detail="Select \"Yes\" to make the application exit")
    if answer == "yes"
        #quit()
        Tcl.messagebox(interp; message="Too bad, bye bye...", buttons="ok")

    elseif answer == "no"
        Tcl.messagebox(interp; message="I know you like this application!",
            buttons="ok")
    end
end

end # module
