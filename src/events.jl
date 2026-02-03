# Processing of Tcl/Tk events. The function `do_events` must be repeatedly called to process
# events when Tk is loaded.

"""
    Tcl.isrunning() -> bool

Return whether the processing of Tcl/Tk events is running.

# See also

[`Tcl.suspend`](@ref), [`Tcl.resume`](@ref), and [`Tcl.do_one_event`](@ref), and
[`Tcl.do_events`](@ref).

"""
isrunning() = (isdefined(runner, 1) && isopen(runner[]))

# Runner called at regular time interval by Julia to process Tcl events.
const runner = Ref{Timer}()

"""
    Tcl.resume(delay=0.1, interval=0.05) -> nothing

Resume or start the processing of Tcl/Tk events with a given `delay` and `interval` both in
seconds. This manages to repeatedly call function [`Tcl.do_events`](@ref). The method
[`Tcl.suspend`](@ref) can be called to suspend the processing of events.

Calling `Tcl.resume` is mandatory when Tk extension is loaded. Thus, the recommended way to
load the Tk package is:

```julia
Tcl.eval(interp, "package require Tk")
Tcl.resume()
```

or alternatively:

```julia
tk_start()
```

can be called to do that.

"""
function resume(delay::Real=0.1, interval::Real=0.05)
    if !isrunning()
        if VERSION ≥ v"1.12"
            # We want the callback to run in the calling thread.
            runner[] = Timer(do_events, delay; interval=interval, spawn=false)
        else
            runner[] = Timer(do_events, delay; interval=interval)
        end
    end
    return nothing
end

"""
    Tcl.suspend() -> nothing

Suspend the processing of Tcl/Tk events for all interpreters. The method
[`Tcl.resume`](@ref) can be called to resume the processing of events.

"""
function suspend()
    isrunning() && close(runner[])
    return nothing
end

"""
    Tcl.do_events(flags = TCL_DONT_WAIT|TCL_ALL_EVENTS) -> num::Int

Process Tcl/Tk events for all interpreters by calling [`Tcl.do_one_event(flags)`](@ref)
until there are no events matching `flags` and return the number of processed events.
Normally this is automatically called by the timer set by [`Tcl.resume`](@ref).

"""
do_events(::Timer) = do_events()

function do_events(flags::Integer = default_event_flags)
    num = 0
    while do_one_event(flags)
        num += 1
    end
    return num
end

@deprecate doevents(args...; kwds...) do_events(args...; kwds...)

const default_event_flags = TCL_DONT_WAIT|TCL_ALL_EVENTS

"""
    Tcl.do_one_event(flags = TCL_DONT_WAIT|TCL_ALL_EVENTS) -> bool

Process at most one Tcl/Tk event for all interpreters matching `flags` and return whether
one such event was processed. This function is called by [`Tcl.do_events`](@ref).

"""
do_one_event(flags::Integer = default_event_flags) = !iszero(Tcl_DoOneEvent(flags))
