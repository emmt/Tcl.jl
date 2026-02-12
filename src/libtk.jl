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

"""
    ImageBlock{T,I}(pointer::Ptr, width::Integer, height::Integer, pitch::Integer,
                    step::Integer, offset::NTuple{4,Integer}) -> block

Return a structure describing a block of pixels in an image. `T` is the pixel type, `I` is
the integer type for most fields. Fields are:

* `block.pointer::Ptr{T}` is the pointer to the first pixel of the block;

* `block.width::I` is the width, in pixels, of the block;

* `block.height::I` is the height, in pixels, of the block;

* `block.pitch::I` is the offset, in bytes, between corresponding pixels in successive lines
  of the block;

* `block.step::I` is the offset, in bytes, between successive pixels in the same line of the
  block;

* `block.offset::NTuple{4,I}` is the tuple of offsets, in bytes, for the *red*, *green*,
  **blue*, and alpha* components of a pixel (the latter is negative if there is no *alpha*
  *channel).

There are two other constructors where all fields can be specified by keywords:

```julia
ImageBlock{T,I}(; kwds...)
ImageBlock{T,I}(block::ImageBlock; kwds...)
```

The `block` argument, if specified, provides default values for the fields of the returned
block. If `block` is unspecified, all keywords are mandatory.

"""
struct ImageBlock{T #= pixel type =#, I<:Integer}
    # NOTE Order is important so that `Tk_PhotoImageBlock` is just `ImageBlock{UInt8,Cint}`
    pointer::Ptr{T}
    width::I
    height::I
    pitch::I
    step::I
    offset::NTuple{4,I}
end

"""
    Tk_PhotoImageBlock

Alias to the Julia type for the `Tk_PhotoImageBlock` C structure which (in `<tk.h>`) is
defined as something equivalent to:

```julia
struct Tk_PhotoImageBlock
    # Offsets are in bytes, dimensions are in pixels.
    pointer::Ptr{UInt8} # `pixelPtr` in <tk.h>
    width::Cint
    height::Cint
    pitch::Cint
    step::Cint # `pixelSize` in <tk.h>
    offset::NTuple{4,Cint}
end
```

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
