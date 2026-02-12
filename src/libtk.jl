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

struct ImageBlock{T #= pixel type =#, I<:Integer}
    # Offsets are in bytes, dimensions are in pixels.
    # NOTE Order is important so that `Tk_PhotoImageBlock` is just
    #      `ImageBlock{UInt8,Cint}`
    pointer::Ptr{T}      # pointer to the first pixel
    width::I             # width of block, in pixels
    height::I            # height of block, in pixels
    pitch::I             # offset between corresponding pixels in successive lines
    step::I              # offset between successive pixels in the same line
    channel::NTuple{4,I} # offsets for the red, green, blue, and alpha and alpha
                         # components of the pixel (negative if missing)
end

"""
    Tk_PhotoImageBlock

Alias to the Julia type equivalent to `Tk_PhotoImageBlock` C structure which, according to
`<tk.h>` could have been defined as:

```julia
struct Tk_PhotoImageBlock
    # Offsets are in bytes, dimensions are in pixels.
    pixelPtr::Ptr{UInt8}   # pointer to the first pixel
    width::Cint            # width of block, in pixels
    height::Cint           # height of block, in pixels
    pitch::Cint            # offset between corresponding pixels in successive lines
    pixelSize::Cint        # offset between successive pixels in the same line
    offset::NTuple{4,Cint} # offsets for the red, green, blue, and alpha and alpha
                           # components of the pixel
end
```

In the `Tk_PhotoImageBlock` alias some field names have changed:

* `pixelPtr -> pointer`;
* `pixelsSize -> step`;
* `offset -> channel`;

"""
const Tk_PhotoImageBlock = ImageBlock{UInt8,Cint}

function Tk_FindPhoto(interp, name)
    @ccall libtk.Tk_FindPhoto(interp::Ptr{Tcl_Interp}, name::Cstring)::Tk_PhotoHandle
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
