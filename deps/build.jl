using Libdl
libtcl = get(ENV, "JL_LIBTCL", nothing)
libtk = get(ENV, "JL_LIBTK", nothing)
use_artifacts = (libtcl == nothing && libtk == nothing)
path = joinpath(@__DIR__, "deps.jl")
open(path, "w") do io
    println(io, "# Tcl/Tk dynamic libraries.")
    if use_artifacts
        println(io, "import Tcl_jll, Tk_jll")
        println(io, "const libtcl = Tcl_jll.libtcl")
        println(io, "const libtk = Tk_jll.libtk")
    else
        isfile(libtcl) || error(
            "Environment variable `JL_LIBTCL` is not set with the path of an existing file")
        isfile(libtk) || error(
            "Environment variable `JL_LIBTK` is not set with the path of an existing file")
        println(io, "const libtcl = \"$(escape_string(libtcl))\"")
        println(io, "const libtk = \"$(escape_string(libtk))\"")
    end
end
module Deps
include("deps.jl")
end
handle = Libdl.dlopen(Deps.libtcl)
refs = [Ref{Cint}() for _ in 1:4]
func = Libdl.dlsym(handle, :Tcl_GetVersion)
ccall(func, Cvoid, (Ptr{Cint},Ptr{Cint},Ptr{Cint},Ptr{Cint}), refs[1], refs[2], refs[3], refs[4])
major, minor, patch, release = map(x -> x[], refs)
TCL_VERSION = if release == 0
    VersionNumber(major, minor, patch, ("alpha",))
elseif release == 1
    VersionNumber(major, minor, patch, ("beta",))
else
    release == 2 || @warn "unknown Tcl release $release"
    VersionNumber(major, minor, patch)
end
open(path, "a") do io
    println(io, "")
    println(io, "# Tcl/Tk version.")
    println(io, "const TCL_VERSION = v\"$(TCL_VERSION)\"")
    println(io, "const TCL_MAJOR_VERSION = $(major)")
    println(io, "const TCL_MINOR_VERSION = $(minor)")
end
if use_artifacts
    # With Tcl/Tk artifacts, global variable `tcl_library` must be initialized to the
    # directory of `init.tcl` before calling `Tcl_Init` and global variable `tk_library`
    # must be initialized to the directory of `tk.tcl` before calling `Tk_Init`.
    if major < 9
        # Starting with Tcl 9, scripts may be embedded as a zip file-system in the libraries
        # so we only check whether the scripts exist for older Tcl versions.
        tcl_library = joinpath(dirname(dirname(Deps.Tcl_jll.libtcl_path)), "lib", "tcl$(major).$(minor)")
        tcl_init = joinpath(tcl_library, "init.tcl")
        isfile(tcl_init) || error("Tcl initialization script `init.tcl` not found in `$tcl_library`")
        tk_library = joinpath(dirname(dirname(Deps.Tk_jll.libtk_path)), "lib", "tk$(major).$(minor)")
        tk_init = joinpath(tk_library, "tk.tcl")
        isfile(tk_init) || error("Tk initialization script `tk.tcl` not found in `$tk_library`")
    end
    open(path, "a") do io
        println(io, "")
        println(io, "# Directory where is Tcl initialization script `init.tcl`.")
        println(io, "const TCL_LIBRARY = joinpath(dirname(dirname(Tcl_jll.libtcl_path)), \"lib\", \"tcl\$(TCL_MAJOR_VERSION).\$(TCL_MINOR_VERSION)\")")
        println(io, "")
        println(io, "# Directory where is Tk initialization script `tk.tcl`.")
        println(io, "const TK_LIBRARY = joinpath(dirname(dirname(Tk_jll.libtk_path)), \"lib\", \"tk\$(TCL_MAJOR_VERSION).\$(TCL_MINOR_VERSION)\")")
    end
end
