import ColorTypes, FixedPointNumbers

TkImage(obj::TkObject, kind::Name, args...; kwds...) =
    TkImage(getinterp(obj), kind, args; kwds...)

TkImage(interp::TclInterp, kind::Name; kwds...) =
    __wrapimage(interp, kind,
                tcleval(interp, "image", "create", kind; kwds...))

function TkImage(interp::TclInterp, kind::AbstractString,
                 name::AbstractString; kwds...)
    if tcltry(interp, "image", "type", name) == TCL_OK
        # Image already exists.
        if kind != getresult(interp)
            tclerror("image exists with a different type")
        end
        if length(kwds) > 0
            tcleval(interp, name, "configure"; kwds...)
        end
    else
        name = tcleval(interp, "image", "create", kind, name; kwds...)
    end
    return __wrapimage(interp, kind, name)
end

function __wrapimage(interp::TclInterp, kind::AbstractString,
                     name::AbstractString)
    T = Symbol(string(lowercase(kind[1]), lowercase(kind[2:end])))
    return TkImage{T}(interp, name)
end

(img::TkImage)(args...; kdws...) =
    evaluate(img.interp, img, args...; kwds...)

@inline getinterp(img::TkImage) = img.interp

@inline getpath(img::TkImage) = img.path

@inline TclObj{T<:TkImage}(img::T) = TclObj{T}(__newobj(getpath(img)))

delete(img::TkImage) =
    evaluate(getinterp(img), "delete", getpath(img))

getwidth(img::TkImage) =
    Parse(Int, evaluate(getinterp(img), "width", getpath(img)))

getheight(img::TkImage) =
    Parse(Int, evaluate(getinterp(img), "height", getpath(img)))

exists(img::TkImage) =
    tcltry(getinterp(img), "image", "inuse", getpath(img)) == TCL_OK

Base.resize!(img::TkImage{:Photo}, args...) =
    setphotosize(getinterp(img), getpath(img), args...)

Base.size(img::TkImage{:Photo}) =
    getphotosize(getinterp(img), getpath(img))

function Base.size(img::TkImage{:Photo}, i::Integer)
    i ≥ 1 || throw(BoundsError("out of bounds dimension index"))
    return (i ≤ 2 ? size(img)[i] : 1)
end

Base.size(img::TkImage) =
    getwidth(img), getheight(img)

function Base.size(img::TkImage, i::Integer)
    i ≥ 1 || throw(BoundsError("out of bounds dimension index"))
    return (i == 1 ? getwidth(img) :
            i == 2 ? getheight(img) :
            1)
end

#------------------------------------------------------------------------------
# Apply a "color" map to an array of gray levels.

colorize{T<:Real,N,C}(arr::Array{T,N}, lut::AbstractVector{C}; kwds...) =
    colorize!(Array{C}(size(arr)), arr, lut; kwds...)

function colorize!{T<:Real,N,C}(dst::Array{C,N}, arr::Array{T,N},
                                lut::AbstractVector{C};
                                cmin::Union{Real,Void} = nothing,
                                cmax::Union{Real,Void} = nothing)
    # Get the clipping values (not needed if number of color levels smaller
    # than 2).
    local _cmin::T, _cmax::T
    if length(lut) < 2
        @assert length(arr) ≥ 1
        _cmin = _cmax = arr[1]
    elseif isa(cmin, Void)
        if isa(cmax, Void)
            _cmin, _cmax = extrema(arr)
        else
            _cmin, _cmax = minimum(arr), cmax
        end
    else
        if isa(cmax, Void)
            _cmin, _cmax = cmin, maximum(arr)
        else
            _cmin, _cmax = cmin, cmax
        end
    end
    colorize!(dst, arr, _cmin, _cmax, lut)
end

function threshold!{T<:Real,N,C}(dst::AbstractArray{C,N},
                                 src::AbstractArray{T,N},
                                 lvl::T, lo::C, mid::C, hi::C)
    @assert size(dst) == size(src)
    @inbounds for i in eachindex(dst, src)
        val = src[i]
        dst[i] = (val < lvl ? lo :
                  val > lvl ? hi :
                  mid)
    end
    return dst
end

function colorize!{T<:Real,N,C}(dst::Array{C,N},
                                arr::Array{T,N},
                                cmin::T, cmax::T,
                                lut::AbstractVector{C}) :: Array{C,N}
    @assert size(dst) == size(arr)
    n = length(lut)
    @assert length(arr) ≥ 1
    @assert 1 ≤ n

    if n < 2
        # Just fill the result with the same look-up table entry.
        fill!(dst, lut[1])
    elseif cmin == cmax
        # Perform a thresholding.
        threshold!(dst, src, cmin, lut[1], lut[div(n,2)+1], lut[n])
    else
        # Use at least Float32 for the computations.
        R = promote_type(Float32, T)
        const kmin = 1
        const kmax = n
        const scl = R(kmax - kmin)/(R(cmax) - R(cmin))
        const off = R(cmin*kmax - cmax*kmin)/R(kmax - kmin)
        # FIXME: adjust cmin and cmax to speedup
        # adj = (cmax - cmin)/(2*(kmax - kmin))
        # cmin += zadj
        # cmax -= zadj
        if scl > zero(R)
            @inbounds for i in eachindex(dst, src)
                val = src[i]
                k = (val ≤ cmin ? kmin :
                     val ≥ cmax ? kmax :
                     round(Int, (R(val) - off)*scl)) :: Int
                dst[i] = lut[k]
            end
        else
            @inbounds for i in eachindex(dst, src)
                val = src[i]
                k = (val ≥ cmin ? kmin :
                     val ≤ cmax ? kmax :
                     round(Int, (R(val) - off)*scl)) :: Int
                dst[i] = lut[k]
            end
        end
    end
    return dst
end

#------------------------------------------------------------------------------
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
    green::Cint
    blue::Cint
    alpha::Cint

    TkPhotoImageBlock() = new(C_NULL,0,0,0,0,0,0,0,0)
end

findphoto(img::TkImage) = findphoto(getinterp(img), getpath(img))

function findphoto(interp::TclInterp, name::AbstractString)
    imgptr = ccall((:Tk_FindPhoto, libtk), Ptr{Void},
                   (Ptr{Void}, Ptr{UInt8}), interp.ptr, name)
    if imgptr == C_NULL
        tclerror("invalid image name")
    end
    return imgptr
end

getpixels(img::TkImage, args...) =
    getpixels(getinterp(img), getpath(img), args...)

getpixels(name::Name, args...) =
    getpixels(getinterp(), name, args...)

getpixels(interp::TclInterp, name::Symbol, args...) =
    getpixels(interp, string(name), args...)

function getpixels(interp::TclInterp, name::AbstractString,
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
            # FIXME: computaions should be done with UInt16?
            dst[x,y] = ((77*src[r,x,y] + 151*src[g,x,y] +
                         28*src[b,x,y] + 128) >> 8)
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

getphotosize(img::TkImage) =
    getphotosize(getinterp(img), getpath(img))

function getphotosize(interp::TclInterp, name::AbstractString)
    w, h = __getphotosize(findphoto(interp, name))
    return (Int(w), Int(h))
end

function setphotosize(interp::TclInterp, name::AbstractString, width::Integer,
                      height::Integer)
    __setphotosize(interp, findphoto(interp, name), Cint(width), Cint(height))
end

function __getphotosize(imgptr::Ptr{Void})
    width, height = Ref{Cint}(0), Ref{Cint}(0)
    if imgptr != C_NULL
        ccall((:Tk_PhotoGetSize, libtk), Void,
              (Ptr{Void}, Ref{Cint}, Ref{Cint}),
              imgptr, width, height)
    end
    return (width[], height[])
end

function __setphotosize(interp::TclInterp, imgptr::Ptr{Void},
                        width::Cint, height::Cint)
    code = ccall((:Tk_PhotoSetSize, libtk), Cint,
                 (TclInterpPtr, Ptr{Void}, Cint, Cint),
                 interp.ptr, imgptr, width, height)
    code == TCL_OK || tclerror(tclresult(interp))
    return nothing
end

function __expandphotosize(interp::TclInterp, imgptr::Ptr{Void},
                           width::Cint, height::Cint)
    code = ccall((:Tk_PhotoExpand, libtk), Cint,
                 (TclInterpPtr, Ptr{Void}, Cint, Cint),
                 interp.ptr, imgptr, width, height)
    code == TCL_OK || tclerror(tclresult(interp))
    return nothing
end

function __setpixels(interp::TclInterp, name::AbstractString,
                     block::TkPhotoImageBlock,
                     x::Cint = Cint(0), y::Cint = Cint(0),
                     composite::Cint = TK_PHOTO_COMPOSITE_SET)
    # Get photo image.
    imgptr = findphoto(interp, name)
    width, height = __getphotosize(imgptr)
    println("image size: $width x $height")

    # Resize the image if it is too small.
    if width < x + block.width || height < y + block.height
        # Not clear (from Tcl/Tk doc.) why the following should be done and I
        # had to dive into the source code TkImgPhoto.c to figure out how to
        # actually resize the image (just calling Tk_PhotoSetSize with the
        # correct size yields segmentation fault).
        width = max(width, x + block.width)
        height = max(height, y + block.height)
        __setphotosize(interp, imgptr, zero(Cint), zero(Cint))
        __expandphotosize(interp, imgptr, width, height)
    end

    width, height = __getphotosize(imgptr)
    println("image size: $width x $height")


    # Assume (TCL_MAJOR_VERSION == 8) && (TCL_MINOR_VERSION >= 5), for older
    # versions, the interpreter argument is missing in Tk_PhotoPutBlock.
    code = ccall((:Tk_PhotoPutBlock, libtk), Cint,
                 (Ptr{Void}, Ptr{Void}, Ptr{TkPhotoImageBlock},
                  Cint, Cint, Cint, Cint, Cint),
                 interp.ptr, imgptr, &block, x, y,
                 block.width, block.height, composite)
    code == TCL_OK || tclerror(tclresult(interp))

    if false
        # Notify that image has changed (FIXME: not needed as it is done by
        # Tk_PhotoPutBlock).
        ccall((:Tk_ImageChanged, libtk), Void,
              (Ptr{Void}, Cint, Cint, Cint, Cint, Cint, Cint),
              imgptr, x, y, block.width, block.height,
              width, height)
    end

    return nothing
end

setpixels(img::TkImage{:Photo}, args...) =
    setpixels(getinterp(img), getpath(img), args...)

setpixels(name::Name, args...) = setpixels(getinterp(), name, args...)

setpixels(interp::TclInterp, name::Symbol, args...) =
    setpixels(interp, string(name), args...)

function setpixels(interp::TclInterp, name::AbstractString,
                   src::DenseArray{UInt8,3})
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
    __setpixels(interp, name, block)
end

typealias Normed8 FixedPointNumbers.Normed{UInt8,8}
typealias Gray8 Union{UInt8,TkGray{UInt8},ColorTypes.Gray{Normed8}}
typealias RGB24 Union{TkRGB{UInt8},ColorTypes.RGB{Normed8}}
typealias BGR24 Union{TkBGR{UInt8},ColorTypes.BGR{Normed8}}
typealias RGBA32 Union{TkRGBA{UInt8},ColorTypes.RGBA{Normed8}}
typealias BGRA32 Union{TkBGRA{UInt8},ColorTypes.BGRA{Normed8}}
typealias ARGB32 Union{TkARGB{UInt8},ColorTypes.ARGB{Normed8}}
typealias ABGR32 Union{TkABGR{UInt8},ColorTypes.ABGR{Normed8}}

for (T, r, g, b, a) in ((:Gray8,  0, 0, 0, 0),
                        (:RGB24,  0, 1, 2, 0),
                        (:BGR24,  2, 1, 0, 0),
                        (:RGBA32, 0, 1, 2, 3),
                        (:BGRA32, 2, 1, 0, 3),
                        (:ARGB32, 1, 2, 3, 0),
                        (:ABGR32, 3, 2, 1, 0))
    @eval function setpixels{T<:$T}(interp::TclInterp, name::AbstractString,
                                    A::DenseArray{T,2})
        block = TkPhotoImageBlock()
        block.ptr       = pointer(A)
        block.pixelsize = sizeof(T)
        block.width     = size(A, 1)
        block.height    = size(A, 2)
        block.pitch     = block.pixelsize*block.width
        block.red       = $r
        block.green     = $g
        block.blue      = $b
        block.alpha     = $a
        __setpixels(interp, name, block)
    end
end

