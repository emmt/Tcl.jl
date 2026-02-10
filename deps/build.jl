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
