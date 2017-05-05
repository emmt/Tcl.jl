# Implement reading/writing of Tk "photo" images.

type TkPhotoImageBlock
    # Pointer to the first pixel.
    ptr::Ptr{UInt8}

    # Width of block, in pixels.
    width::Cint

    # Height of block, in pixels.
    height::Cint

    # Address difference between corresponding pixels in successive lines.
    pitch::Cint

    # Address difference between successive pixels in the same line.
    pixelsize::Cint

    # Address differences between the red, green, blue and alpha components of
    # the pixel and the pixel as a whole.
    red::Cint
    blue::Cint
    green::Cint
    alpha::Cint

    TkPhotoImageBlock() = new(C_NULL,0,0,0,0,0,0,0,0)
end

function findphoto(interp::TclInterp, name::String)
    imgptr = ccall((:Tk_FindPhoto, libtk), Ptr{Void},
                   (Ptr{Void}, Ptr{UInt8}), interp.ptr, name)
    if imgptr == C_NULL
        tclerror("invalid image name")
    end
    return imgptr
end

getpixels(name::Name, args...) = getpixels(defaultinterpreter(), name, args...)

getpixels(interp::TclInterp, name::Symbol, args...) =
    getpixels(interp, string(name), args...)

function getpixels(interp::TclInterp, name::String,
                   colormode::Symbol = :gray)
    # Get photo image data.
    imgptr = findphoto(interp, name)
    block = TkPhotoImageBlock()
    code = ccall((:Tk_PhotoGetImage, libtk), Cint,
                 (Ptr{Void}, Ptr{TkPhotoImageBlock}),
                 imgptr, &block)
    if code != 1
        error("unexpected returned code")
    end
    width     = Int(block.width)
    height    = Int(block.height)
    pixelsize = Int(block.pixelsize)
    pitch     = Int(block.pitch)
    @assert pitch ≥ width*pixelsize
    @assert rem(pitch, pixelsize) == 0
    src = unsafe_wrap(Array, block.ptr,
                      (pixelsize, div(pitch, pixelsize), height), false)
    r = 1 + Int(block.red)
    g = 1 + Int(block.green)
    b = 1 + Int(block.blue)
    a = 1 + Int(block.alpha)

    if colormode == :gray
        # Below is an approximation to:
        #	GRAY = 0.30*RED + 0.59*GREEN + 0.11*BLUE
        # rounded to nearest integer.
        #
        dst = Array{UInt8}(width, height)
        for y in 1:height, x in 1:width
            dst[x,y] = ((77*src[r,x,y] + 151*src[g,x,y]+ 28*src[b,x,y] + 128)>>8)
        end
    elseif colormode == :red
        dst = Array{UInt8}(width, height)
        for y in 1:height, x in 1:width
            dst[x,y] = src[r,x,y]
        end
    elseif colormode == :green
        dst = Array{UInt8}(width, height)
        for y in 1:height, x in 1:width
            dst[x,y] = src[g,x,y]
        end
    elseif colormode == :blue
        dst = Array{UInt8}(width, height)
        for y in 1:height, x in 1:width
                dst[x,y] = src[b,x,y]
        end
    elseif colormode == :alpha
        dst = Array{UInt8}(width, height)
        for y in 1:height, x in 1:width
                dst[x,y] = src[a,x,y]
        end
    elseif colormode == :rgb
        dst = Array{UInt8}(3, width, height)
        for y in 1:height, x in 1:width
            dst[1,x,y] = src[r,x,y]
            dst[2,x,y] = src[g,x,y]
            dst[3,x,y] = src[b,x,y]
        end
    elseif colormode == :rgba
        dst = Array{UInt8}(4, width, height)
        for y in 1:height, x in 1:width
            dst[1,x,y] = src[r,x,y]
            dst[2,x,y] = src[g,x,y]
            dst[3,x,y] = src[b,x,y]
            dst[4,x,y] = src[a,x,y]
        end
    else
        error("invalid color mode")
    end
    return dst
end

function getphotosize(interp::TclInterp, name::String)
    w, h = _getphotosize(findphoto(interp, name))
    return (Int(w), Int(h))
end

setphotosize(interp::TclInterp, name::String, width::Integer, height::Integer) =
    _setphotosize(interp, findphoto(interp, name),
                  Cint(width), Cint(height))

function _getphotosize(imgptr::Ptr{Void})
    width, height = Ref{Cint}(0), Ref{Cint}(0)
    if imgptr != C_NULL
        ccall((:Tk_PhotoGetSize, libtk), Void, (Ptr{Void}, Ref{Cint}, Ref{Cint}),
              imgptr, width, height)
    end
    return (width[], height[])
end

function _setphotosize(interp::TclInterp, imgptr::Ptr{Void},
                       width::Cint, height::Cint)
    code = ccall((:Tk_PhotoSetSize, libtk), Cint,
                 (Ptr{Void}, Ptr{Void}, Cint, Cint),
                 interp.ptr, imgptr, width, height)
    if code != TCL_OK
        tclerror(tclresult(interp))
    end
    return nothing
end

function _setpixels(interp::TclInterp, name::String,
                    block::TkPhotoImageBlock,
                    x::Cint = Cint(0), y::Cint = Cint(0),
                    composite::Cint = TK_PHOTO_COMPOSITE_SET)
    # Get photo image.
    imgptr = findphoto(interp, name)
    width, height = _getphotosize(imgptr)

    # Set the image pixels.
    if width < x + block.width || height < y + block.height
        width = max(width, x + block.width)
        height = max(height, y + block.height)
        _setphotosize(interp, imgptr, width, height)
    end

    # Assume (TCL_MAJOR_VERSION == 8) && (TCL_MINOR_VERSION >= 5), for older
    # versions, the interpreter argument is missing in Tk_PhotoPutBlock.
    code = ccall((:Tk_PhotoPutBlock, libtk), Cint,
                 (Ptr{Void}, Ptr{Void}, Ptr{TkPhotoImageBlock},
                  Cint, Cint, Cint, Cint, Cint),
                 interp.ptr, imgptr, &block, x, y, width, height, composite)
    if code != TCL_OK
        tclerror(tclresult(interp))
    end

    # Notify that image has changed.
    ccall((:Tk_ImageChanged, libtk), Void,
          (Ptr{Void}, Cint, Cint, Cint, Cint, Cint, Cint),
          imgptr, x, y, x + block.width, y + block.height,
          width, height)

    return nothing
end

setpixels(name::Name, args...) = setpixels(defaultinterpreter(), name, args...)

setpixels(interp::TclInterp, name::Symbol, args...) =
    setpixels(interp, string(name), args...)

function setpixels(interp::TclInterp, name::String,
                   src::AbstractArray{UInt8,2})
    block = TkPhotoImageBlock()
    block.ptr       = pointer(src)
    block.pixelsize = 1
    block.width     = size(src, 1)
    block.height    = size(src, 2)
    block.pitch     = block.pixelsize*block.width
    block.red       = 0
    block.green     = 0
    block.blue      = 0
    block.alpha     = 0
    _setpixels(interp, name, block)
end

function setpixels(interp::TclInterp, name::String,
                   src::AbstractArray{UInt8,3})

    block = TkPhotoImageBlock()
    block.ptr       = pointer(src)
    block.pixelsize = size(src, 1)
    block.width     = size(src, 2)
    block.height    = size(src, 3)
    block.pitch     = block.pixelsize*block.width
    if block.pixelsize == 3
        block.red   = 0;
        block.green = 1;
        block.blue  = 2;
        block.alpha = 0;
    elseif block.pixelsize == 4
        block.red   = 0;
        block.green = 1;
        block.blue  = 2;
        block.alpha = 3;
    else
        error("invalid first dimension")
    end
    _setpixels(interp, name, block)
end

function runtests()
    interp = Tcl.TclInterp();
    interp("package require Tk");
    Tcl.resume()
    name = interp("image create photo -file /home/eric/work/code/CImg/CImg-1.5.5/examples/img/lena.pgm")
    interp("pack [button .b -image $name]")
    d = Tcl.getpixels(interp, name, :red);
    return d;
end
