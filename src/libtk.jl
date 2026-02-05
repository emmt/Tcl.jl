# libtk.jl -
#
# Low level glue code to C functions of the Tk library.
#

#---------------------------------------------------------------------------- Photo images -

# The following values control how blocks are combined into photo images when the alpha
# component of a pixel is not 255, a.k.a. the compositing rule.
const TK_PHOTO_COMPOSITE_OVERLAY = Cint(0)
const TK_PHOTO_COMPOSITE_SET     = Cint(1)

# Opaque photo handle.
abstract type Tk_PhotoHandle_ end
const Tk_PhotoHandle = Ptr{Tk_PhotoHandle_}

mutable struct Tk_PhotoImageBlock
    # Pointer to the first pixel.
    pixelPtr::Ptr{UInt8}

    # Width of block, in pixels.
    width::Cint

    # Height of block, in pixels.
    height::Cint

    # Address difference between corresponding pixels in successive lines.
    pitch::Cint

    # Address difference between successive pixels in the same line.
    pixelSize::Cint

    # Address differences between the red, green, blue and alpha components of the pixel and
    # the pixel as a whole.
    offset::NTuple{4,Cint} # red, green, blue, and alpha

    Tk_PhotoImageBlock() = new(C_NULL,0,0,0,0,0,0,0,0)
end

function Tk_FindPhoto(interp, name)
    @ccall libtk.Tk_PhotoSetSize(interp::Ptr{Tcl_Interp}, name::Cstring)::Tk_PhotoHandle
end

function Tk_PhotoPutBlock(interp, handle, block, x, y, width, height, compRule)
    @ccall libtk.Tk_PhotoPutBlock(interp::Ptr{Tcl_Interp}, handle::Tk_PhotoHandle,
                                  block::Ptr{Tk_PhotoImageBlock}, x::Cint, y::Cint,
                                  width::Cint, height::Cint, compRule::Cint)::TclStatus
end

function Tk_PhotoPutZoomedBlock(interp, handle, block, x, y, width, height,
                                zoomX, zoomY, subsampleX, subsampleY, compRule)
    @ccall libtk.Tk_PhotoPutZoomedBlock(interp::Ptr{Tcl_Interp}, handle::Tk_PhotoHandle,
                                        block::Ptr{Tk_PhotoImageBlock}, x::Cint, y::Cint,
                                        width::Cint, height::Cint, zoomX::Cint, zoomY::Cint,
                                        subsampleX::Cint, subsampleY::Cint,
                                        compRule::Cint)::TclStatus
end

function Tk_PhotoGetImage(handle, block)
    # NOTE Tk_PhotoGetImage always return 1
    @ccall libtk.Tk_PhotoGetImage(handle::Tk_PhotoHandle,
                                  block::Ptr{Tk_PhotoImageBlock})::Cint
end

function Tk_PhotoBlank(handle)
    @ccall libtk.Tk_PhotoBlank(handle::Tk_PhotoHandle)::Cvoid
end

function Tk_PhotoExpand(interp, handle, width, height)
    @ccall libtk.Tk_PhotoExpand(interp::Ptr{Tcl_Interp}, handle::Tk_PhotoHandle,
                                width::Cint, height::Cint)::TclStatus
end

function Tk_PhotoGetSize(handle, width, height)
    @ccall libtk.Tk_PhotoGetSize(handle::Tk_PhotoHandle,
                                 width::Ptr{Cint}, height::Ptr{Cint})::Cvoid
end

function Tk_PhotoSetSize(interp, handle, width, height)
    @ccall libtk.Tk_PhotoSetSize(interp::Ptr{Tcl_Interp}, handle::Tk_PhotoHandle,
                                 width::Cint, height::Cint)::TclStatus
end
