#
# macros.jl -
#
# Definition of private macros for Julia Tcl interface.
#

# The following macro is used to build a list out of given arguments and
# keywords by the `exec` and `list` methods.
macro __build_list(listptr, args, kwds)
    quote
        for arg in $(esc(args))
            __lappend($(esc(listptr)), arg)
        end
        for (key, val) in $(esc(kwds))
            __lappendoption($(esc(listptr)), key, val)
        end
    end
end

# The following macro is used to build a list by concatenating given arguments
# keywords by the `eval` and `concat` methods.
macro __concat_args(listptr, args)
    quote
        for arg in $(esc(args))
            __concat($(esc(listptr)), arg)
        end
    end
end
