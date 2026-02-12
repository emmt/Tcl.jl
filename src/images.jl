#
# images.jl -
#
# Manipulation of Tk images.
#

"""
    TkImage{type}(interp=TclInterp(), option => value, ...) -> img
    TkImage{type}(interp=TclInterp(), name, option => value, ...) -> img

    TkImage{type}(w::TkWidget, option => value, ...) -> img
    TkImage{type}(w::TkWidget, name, option => value, ...) -> img

Return a Tk image of given `type` (e.g., `:bitmap`, `:pixmap`, or `:photo`).

!!! note
    `Tk` extension must have been loaded in the interpreter before creating an image.
    This can be done with [`tk_start`](@ref).

`interp` is the Tcl interpreter where lives the image (the shared interpreter of the thread
by default). If a Tk widget `w` is specified, its interpreter is used.

If the image `name` is not specified, it is automatically generated. If `name` is specified
and an image with this name already exists in the interpreter, it is re-used and, if options
are specified, it is reconfigured.

There may be any `option => value` pairs to (re)configure the image. Options depend on the
image types.

A Tk image can then be used in any Tcl/Tk script or command where an image is expected.

Tk images implement the abstract array API. To extract the pixels of an image, the
`img[x,y]` syntax may be used with `x` and `y` pixel indices or ranges. For a `:photo`
image, pixel values are represented by `RGBA{N0f8}` colors.

A Tk image has a number of properties:

```julia
img.inuse    # whether an image is in use in a Tk widget
img.width    # the width of the image in pixels
size(img, 1) # idem
img.height   # the height of the image in pixels
size(img, 2) # idem
img.size     # (width, height)
size(img)    # idem
img.type     # the symbolic type of the image (`:bitmap`, `:pixmap`, `:photo`, etc.)
img.name     # the image name in its interpreter
img.interp   # the interpreter hosting the image
```

# See also

[`TkBitmap`](@ref), [`TkPhoto`](@ref), and [`TkPixmap`](@ref) are aliases for specific image
types.

[`tk_start`](@ref), and [`TclInterp`](@ref).

"""
function TkImage{type}(pairs::Pair...) where {type}
    return TkImage{type}(TclInterp(), pairs...)
end
function TkImage{type}(name::Name, pairs::Pair...) where {type}
    return TkImage{type}(TclInterp(), name, pairs...)
end
function TkImage{type}(w::TkWidget, pairs::Pair...) where {type}
    return TkImage{type}(w.interp, name, pairs...)
end
function TkImage{type}(w::TkWidget, name::Name, pairs::Pair...) where {type}
    return TkImage{type}(w.interp, name, pairs...)
end

# Create a new image of a given type and automatically named.
function TkImage{type}(interp::TclInterp, pairs::Pair...) where {type}
    type isa Symbol || argument_error("image type must be a symbol")
    name = interp.exec(:image, :create, type, pairs...)
    return TkImage(Val(type), interp, name)
end

# Create a new image of a given type and name. If an image of the same name already exists,
# it is re-wrapped.
TkImage{type}(interp::TclInterp, name::Name, pairs::Pair...) where {type} =
    TkImage{type}(interp, TclObj(name), pairs...)

function TkImage{type}(interp::TclInterp, name::TclObj, pairs::Pair...) where {type}
    type isa Symbol || argument_error("image type must be a symbol")
    if interp.exec(TclStatus, :image, :type, name) == TCL_OK
        # Image already exists. Possibly configure it and re-wrap it.
        interp.result(TclObj) == type || throw(TclError(
            "image already exists with a different type"))
        length(pairs) > 0 && interp.exec(Nothing, name, :configure, pairs...)
        return TkImage(Val(type), interp, name)
    else
        # Image does not exists. Create a new one and wrap it.
        interp.exec(:image, :create, type, name, pairs...)
        return TkImage(Val(type), interp, name)
    end
end

TclInterp(img::TkImage) = img.interp

# For Tcl, an image is identified by its name.
TclObj(img::TkImage) = img.name
Base.convert(::Type{TclObj}, img::TkImage) = TclObj(img)::TclObj
get_objptr(img::TkImage) = get_objptr(TclObj(img)) # used in `exec`
Base.print(io::IO, img::TkImage) = print(io, img.name)

Base.show(io::IO, ::MIME"text/plain", img::TkImage) = show(io, img)

function Base.show(io::IO, img::T) where {T<:TkImage}
    if T == TkBitmap
        print(io, "TkBitmap (alias for TkImage{:bitmap})")
    elseif T == TkPhoto
        print(io, "TkPhoto (alias for TkImage{:photo})")
    elseif T == TkPixmap
        print(io, "TkPixmap (alias for TkImage{:pixmap})")
    else
        print(io, T)
    end
    dims = size(img)
    print(io, " name = \"", img.name, "\", size = (", dims[1], ", ", dims[2], ")")
    return nothing
end

#-------------------------------------------------------------------------- Image commands -

# Make Tk image objects callable.
(img::TkImage)(args...; kwds...) = Tcl.exec(img.interp, img, args...; kwds...)
(img::TkImage)(::Type{T}, args...; kwds...) where {T} =
    Tcl.exec(T, img.interp, img, args...; kwds...)

# Reproduce Tk `image command ...`.
for (prop, type) in (:delete => :Nothing,
                     :height => :Int,
                     :inuse  => :Bool,
                     :type   => :TclObj,
                     :width  => :Int,
                     )
    func = Symbol("image_", prop)
    @eval begin
        $func(img::TkImage) = $func(img.interp, img.name)
        $func(interp::TclInterp, name::Name) =
            interp.exec($type, :image, $(QuoteNode(prop)), name)
    end
end

# Optimized accessors for Tk photo images.
image_width(img::TkPhoto) = size(img, 1)
image_height(img::TkPhoto) = size(img, 2)

#------------------------------------------------------------------------ Image properties -

Base.propertynames(img::TkImage) = (:height, :interp, :inuse, :name, :size, :type, :width,)
@inline Base.getproperty(img::TkImage, key::Symbol) = _getproperty(img, Val(key))
_getproperty(img::TkImage, ::Val{:height}) = image_height(img)
_getproperty(img::TkImage, ::Val{:interp}) = getfield(img, :interp)
_getproperty(img::TkImage, ::Val{:inuse}) = image_inuse(img)
_getproperty(img::TkImage, ::Val{:name}) = getfield(img, :name)
_getproperty(img::TkImage, ::Val{:size}) = size(img)
_getproperty(img::TkImage{T}, ::Val{:type}) where {T} = T
_getproperty(img::TkImage, ::Val{:width}) = image_width(img)
_getproperty(img::TkImage, ::Val{key}) where {key} = throw(KeyError(key))

#----------------------------------------------------------- Abstract array API for images -

# 32-bit RGBA is the pixel format used by Tk for its photo images.
Base.eltype(::Type{<:TkPhoto}) = RGBA{N0f8}

Base.ndims(img::TkImage) = ndims(typeof(img))
Base.ndims(::Type{<:TkImage}) = 2

Base.IteratorSize(::Type{<:TkImage}) = Base.HasShape{2}()

Base.length(img::TkImage) = prod(size(img))

Base.size(img::TkPhoto) = get_photo_size(img)
function Base.size(img::TkPhoto, i::Integer)
    i < 𝟙 && throw(BoundsError("out of bounds dimension index"))
    return (i ≤ 2 ? size(img)[i] : 1)
end

Base.size(img::TkImage) = (img.width, img.height)
Base.size(img::TkImage, i::Integer) =
    i == 1 ? img.width  :
    i == 2 ? img.height  :
    i ≥ 3 ? 1 : throw(BoundsError("out of bounds dimension index"))

function Base.getindex(img::TkPhoto, ::Colon, ::Colon)
    return read_image(Matrix{eltype(img)}, img)
end

function Base.getindex(img::TkPhoto, xrng::ViewRange, yrng::ViewRange)
    return read_image(Matrix{eltype(img)}, img, xrng, yrng)
end

function Base.getindex(img::TkPhoto, x::Integer, y::Integer)
    GC.@preserve img begin
        block = unsafe_photo_get_image(img)
        return unsafe_load_pixel(eltype(img), block, x, y)
    end
end

#------------------------------------------------------------------------------ Image size -

# Resize Tk photo image. If image must be resized, its contents is not preserved.
Base.resize!(img::TkPhoto, (width, height)::Tuple{Integer,Integer}) =
    resize!(img, width, height)

Base.resize!(img::TkPhoto, width::Integer, height::Integer) =
    photo_resize!(img, width, height)

function get_photo_size(img::TkPhoto)
    GC.@preserve img begin
        width, height = unsafe_get_photo_size(img)
        return (Int(width)::Int, Int(height)::Int)
    end
end

function get_photo_size(interp::TclInterp, name::Name)
    GC.@preserve interp name begin
        width, height = unsafe_get_photo_size(unsafe_find_photo(interp, name))
        return (Int(width)::Int, Int(height)::Int)
    end
end

function photo_resize!(img::TkPhoto, width::Integer, height::Integer)
    width ≥ 𝟘 || argument_error("width must be nonnegative, got $width")
    height ≥ 𝟘 || argument_error("height must be nonnegative, got $height")
    GC.@preserve interp name begin
        handle = unsafe_find_photo(interp, name)
        old_width, old_height = unsafe_photo_get_size(handle)
        if width != old_width || height != old_height
            # Not clear (from Tcl/Tk doc.) why the following should be done and I had to
            # dive into the source code TkImgPhoto.c to figure out how to actually resize
            # the image (just calling Tk_PhotoSetSize with the correct size yields
            # segmentation fault).
            status = Tk_PhotoSetSize(interp, handle, zero(Cint), zero(Cint))
            status == TCL_OK || unsafe_error(interp, "cannot set Tk photo size")
            status = Tk_PhotoExpand(interp, handle, width, height)
            status == TCL_OK || unsafe_error(interp, "cannot expand Tk photo size")
        end
    end
    return nothing
end

#------------------------------------------------------------------------ Read/write image -

function read_image(::Type{Array{T,2}}, img::TkPhoto) where {T<:Colorant}
    GC.@preserve img begin
        block = unsafe_photo_get_image(img)
        return unsafe_copy(Array{T,2}, block)
    end
end

# TODO deal with any ordinal range.
function read_image(::Type{Array{T,2}}, img::TkPhoto,
                    xrng::ViewRange, yrng::ViewRange) where {T<:Colorant}
    GC.@preserve img begin
        block = ImageBlock{UInt8,Int}(unsafe_photo_get_image(img))
        block = restrict_xrange(block, xrng)
        block = restrict_yrange(block, yrng)
        return unsafe_copy(Array{T,2}, block)
    end
end

function read_image(::Type{T}, img::TkPhoto,
                    xrng::Integer, yrng::Integer) where {T<:Colorant}
    GC.@preserve img begin
        block = unsafe_photo_get_image(img)
        block = restrict_xrange(block, xrng)
        block = restrict_yrange(block, yrng)
        return unsafe_copy(Array{T,2}, block)
    end
end

restrict_xrange(block::ImageBlock, ::Colon) = block
function restrict_xrange(block::ImageBlock{T,I}, xrng::AbstractUnitRange) where {T,I}
    ptr = block.pointer
    if isempty(xrng)
        width = zero(I)
    else
        xoff = first(xrng) - 𝟙
        (xoff ≥ 𝟘 && last(xrng) ≤ block.width) || error("out of bounds `x` index range")
        ptr += block.step*xoff
        width = convert(I, length(xrng))
    end
    return ImageBlock{T,I}(block; pointer = ptr, width = width)
end
function restrict_xrange(block::ImageBlock{T,I}, x::Integer) where {T,I}
    (𝟙 ≤ x ≤ block.width) || error("out of bounds `x` index")
    return ImageBlock{T,I}(block; width = one(I),
                           pointer = block.pointer + block.step*(x - 𝟙))
end

restrict_yrange(block::ImageBlock, ::Colon) = block
function restrict_yrange(block::ImageBlock{T,I}, yrng::AbstractUnitRange) where {T,I}
    ptr = block.pointer
    if isempty(yrng)
        height = zero(I)
    else
        yoff = first(yrng) - 𝟙
        (yoff ≥ 𝟘 && last(yrng) ≤ block.height) || error("out of bounds `y` index range")
        ptr += block.pitch*yoff
        height = convert(I, length(yrng))
    end
    return ImageBlock{T,I}(block; pointer = ptr, height = height)
end
function restrict_yrange(block::ImageBlock{T,I}, y::Integer) where {T,I}
    (𝟙 ≤ y ≤ block.height) || error("out of bounds `y` index")
    return ImageBlock{T,I}(block; height = one(I),
                           pointer = block.pointer + block.pitch*(y - 𝟙))
end

# Return the `offset` field of the `ImageBlock` given the pixel type.
offset_from_pixel_type(::Type{UInt8}) = (0, 0, 0, -1)
offset_from_pixel_type(::Type{Gray{T}}) where {T} = (0, 0, 0, -1)
offset_from_pixel_type(::Type{RGB{T}}) where {T} = (n = sizof(T); return (0, n, 2n, -1))
offset_from_pixel_type(::Type{BGR{T}}) where {T} = (n = sizof(T); return (2n, n, 0, -1))
offset_from_pixel_type(::Type{RGBA{T}}) where {T} = (n = sizof(T); return (0, n, 2n, 3n))
offset_from_pixel_type(::Type{ARGB{T}}) where {T} = (n = sizof(T); return (n, 2n, 3n, 0))
offset_from_pixel_type(::Type{BGRA{T}}) where {T} = (n = sizof(T); return (2n, n, 0, 3n))
offset_from_pixel_type(::Type{ABGR{T}}) where {T} = (n = sizof(T); return (3n, 2n, n, 0))

# Constructors for `ImageBlock`.
function ImageBlock(block::ImageBlock; pointer::Ptr{T}, kwds...) where {T}
    return ImageBlock{T}(block; pointer=pointer, kwds...)
end

function ImageBlock{T}(block::ImageBlock; kwds...) where {T}
    return ImageBlock{T,Int}(block; kwds...)
end

function ImageBlock{T,I}(block::ImageBlock;
                         pointer::Ptr = block.pointer,
                         width::Integer = block.width,
                         height::Integer = block.height,
                         pitch::Integer = block.pitch,
                         step::Integer = block.step,
                         offset::NTuple{4,Integer} = block.offset) where {T,I}
    return ImageBlock{T,I}(pointer, width, height, pitch, step, offset)
end

function ImageBlock(; pointer::Ptr{T}, width::Integer, height::Integer,
                    pitch::Integer, step::Integer,
                    offset::NTuple{4,Integer}) where {T}
    return ImageBlock{T,Int}(pointer, width, height, pitch, step, offset)
end

function ImageBlock{T,I}(; pointer::Ptr, width::Integer, height::Integer,
                         pitch::Integer, step::Integer,
                         offset::NTuple{4,Integer}) where {T,I}
    return ImageBlock{T,I}(pointer, width, height, pitch, step, offset)
end

Base.convert(::Type{T}, block::T) where {T<:ImageBlock} = block
Base.convert(::Type{T}, block::ImageBlock) where {T<:ImageBlock} = T(block)::T

# Unsafe.
ImageBlock(arr::DenseMatrix{T}) where {T} = ImageBlock{T}(arr)
ImageBlock{T}(arr::DenseMatrix) where {T} = ImageBlock{T,Int}(arr)
function ImageBlock{T,I}(arr::DenseMatrix{E}) where {T,I,E<:Union{Colorant,UInt8}}
    width, height = size(arr)
    step = sizeof(E)
    return ImageBlock{T,I}(; pointer = pointer(arr),
                           width = width, height = height,
                           pitch = width*step, step = step,
                           offset = offset_from_pixel_type(E))
end

function unsafe_load_pixel(::Type{T}, block::ImageBlock,
                           x::Integer, y::Integer) where {T<:Colorant}
    (𝟙 ≤ x ≤ block.width) || error("out of bounds `x` index")
    (𝟙 ≤ y ≤ block.height) || error("out of bounds `y` index")
    ptr = Ptr{N0f8}(block.pointer) # always N0f8 format for each component
    ptr += block.step*(x - 𝟙) + block.pitch*(y - 𝟙)
    red_off, green_off, blue_off, alpha_off = block.offset
    if red_off == green_off == blue_off
        # Gray image.
        gray = unsafe_load(ptr + red_off)
        if alpha_off < 0 # no alpha channel
            return convert(T, Gray(gray))
        else
            alpha = unsafe_load(ptr + alpha_off)
            return convert(T, RGBA(gray, gray, gray, alpha))
        end
    else
        red   = unsafe_load(ptr +   red_off)
        green = unsafe_load(ptr + green_off)
        blue  = unsafe_load(ptr +  blue_off)
        if alpha_off < 0 # no alpha channel
            return convert(T, RGB(red, green, blue))
        elseif alpha_off == red_off + 3
            alpha = unsafe_load(ptr + alpha_off)
            return convert(T, RGBA(red, green, blue, alpha))
        end
    end
end

function unsafe_copy(::Type{Array{T,2}}, block::ImageBlock) where {T<:Colorant}
    # Pointer to first pixel in red channel (always N0f8 format for each component).
    ptr = Ptr{N0f8}(block.pointer) + block.offset[1]

    # Don't have alpha channel?
    no_alpha_channel = block.offset[4] < 0

    # Offset to other channels (relative to red).
    green_off = block.offset[2] - block.offset[1]
    blue_off  = block.offset[3] - block.offset[1]
    alpha_off = no_alpha_channel ? 0 : block.offset[4] - block.offset[1]

    # Other block parameters.
    width  = Int(block.width )::Int
    height = Int(block.height)::Int
    pitch  = Int(block.pitch )::Int
    step   = Int(block.step  )::Int

    # Allocate destination.
    arr = Array{T}(undef, width, height)

    # Copy image block according to its format.
    generic_rgba = false # 4-channel image in unspecific order?
    if green_off == blue_off == 0
        # Gray image.
        if no_alpha_channel
            # Gray image (no alpha channel).
            unsafe_copy!(arr, Ptr{Gray{N0f8}}(ptr), width, height, pitch, step)
        else
            # Gray image with alpha channel.
            unsafe_copy_gray_alpha!(arr, ptr, ptr + alpha_off, width, height, pitch, step)
        end
    elseif green_off == 1 && blue_off == 2
        if no_alpha_channel
            # RGB storage order (no alpha channel).
            unsafe_copy!(arr, Ptr{RGB{N0f8}}(ptr), width, height, pitch, step)
        elseif alpha_off == 3
            # RGBA storage order.
            unsafe_copy!(arr, Ptr{RGBA{N0f8}}(ptr), width, height, pitch, step)
        elseif alpha_off == -1
            # ARGB storage order.
            unsafe_copy!(arr, Ptr{ARGB{N0f8}}(ptr + alpha_off),
                         width, height, pitch, step)
        else
            # 4-channel image in unspecific order.
            generic_rgba = true
        end
    elseif green_off == -1 && blue_off == -2
        if no_alpha_channel
            # BGR storage order (no alpha channel).
            unsafe_copy!(arr, Ptr{BGR{N0f8}}(ptr + blue_off), width, height, pitch, step)
        elseif alpha_off == 1
            # BGRA storage order.
            unsafe_copy!(arr, Ptr{BGRA{N0f8}}(ptr + blue_off), width, height, pitch, step)
        elseif alpha_off == -3
            # ABGR storage order.
            unsafe_copy!(arr, Ptr{ABGR{N0f8}}(ptr + alpha_off), width, height, pitch, step)
        else
            # 4-channel image in unspecific order.
            generic_rgba = true
        end
    elseif no_alpha_channel
        # 3-channel image in unspecific order.
        unsafe_copy_rgb!(arr, ptr, ptr + green_off, ptr + blue_off,
                         width, height, pitch, step)
    else
        # 4-channel image in unspecific order.
        generic_rgba = true
    end
    if generic_rgba
        # 4-channel image in unspecific order.
        unsafe_copy_rgba!(arr, ptr, ptr + green_off, ptr + blue_off, ptr + alpha_off,
                          width, height, pitch, step)
    end
    return arr
end

# Copy 4-channel image in unspecific order.
function unsafe_copy_rgba!(arr::AbstractMatrix,
                           red_ptr::Ptr, green_ptr::Ptr, blue_ptr::Ptr, alpha_ptr::Ptr,
                           width::Int, height::Int, pitch::Int, step::Int)
    @inbounds for y in 𝟙:height
        @simd for x in 𝟙:width
            off   = pitch*(y - 𝟙) + step*(x - 𝟙)
            red   = unsafe_load(  red_ptr + off)
            green = unsafe_load(green_ptr + off)
            blue  = unsafe_load( blue_ptr + off)
            alpha = unsafe_load(alpha_ptr + off)
            arr[x,y] = RGBA(red, green, blue, alpha)
        end
    end
    return nothing
end

# Copy 3-channel image in unspecific order.
function unsafe_copy_rgb!(arr::AbstractMatrix,
                          red_ptr::Ptr, green_ptr::Ptr, blue_ptr::Ptr,
                          width::Int, height::Int, pitch::Int, step::Int)
    @inbounds for y in 𝟙:height
        @simd for x in 𝟙:width
            off   = pitch*(y - 𝟙) + step*(x - 𝟙)
            red   = unsafe_load(  red_ptr + off)
            green = unsafe_load(green_ptr + off)
            blue  = unsafe_load( blue_ptr + off)
            arr[x,y] = RGB(red, green, blue)
        end
    end
    return nothing
end

# Copy 2-channel (gray + alpha) image in unspecific order.
function unsafe_copy_gray_alpha!(arr::AbstractMatrix,
                                 gray_ptr::Ptr, alpha_ptr::Ptr,
                                 width::Int, height::Int, pitch::Int, step::Int)
    @inbounds for y in 𝟙:height
        @simd for x in 𝟙:width
            off   = pitch*(y - 𝟙) + step*(x - 𝟙)
            gray  = unsafe_load( gray_ptr + off)
            alpha = unsafe_load(alpha_ptr + off)
            arr[x,y] = RGBA(gray, gray, gray, alpha)
        end
    end
    return nothing
end

# Copy pixels in packed format.
function unsafe_copy!(arr::AbstractMatrix, ptr::Ptr,
                      width::Int, height::Int, pitch::Int, step::Int)
    @inbounds for y in 𝟙:height
        @simd for x in 𝟙:width
            arr[x,y] = unsafe_load(ptr + step*(x - 𝟙))
        end
        ptr += pitch
    end
    return nothing
end

#------------------------------------------------------------------------------ Unsafe API -
# Unsafe: arguments must be preserved.

unsafe_find_photo(img::TkPhoto) = unsafe_find_photo(img.interp, img.name)

function unsafe_find_photo(interp::Union{TclInterp,InterpPtr}, name::Name)
    handle = Tk_FindPhoto(interp, name)
    isnull(handle) && TclError("invalid image name")
    return handle
end

unsafe_get_photo_size(img::TkPhoto) = unsafe_get_photo_size(unsafe_find_photo(img))

function unsafe_get_photo_size(handle::Tk_PhotoHandle)
    width = Ref{Cint}(𝟘)
    height = Ref{Cint}(𝟘)
    isnull(handle) || Tk_PhotoGetSize(handle, width, height)
    return (width[], height[])
end

set_photo_size!(interp::TclInterp, name::Name, (width, height)::NTuple{2,Integer}) =
    set_photo_size!(interp, name, width, height)

function set_photo_size!(interp::TclInterp, name::Name, width::Integer, height::Integer)
    GC.@preserve interp begin
        unsafe_photo_set_size!(interp, unsafe_find_photo(interp, name), Cint(width), Cint(height))
    end
end

for (jfunc, (cfunc, mesg)) in (:unsafe_photo_set_size! => (:Tk_PhotoSetSize,
                                                           "cannot set Tk photo size"),
                               :unsafe_photo_expand! => (:Tk_PhotoExpamd,
                                                         "cannot expand Tk photo"),
                               )
    @eval begin
        function $jfunc(interp::TclInterp, handle::Tk_PhotoHandle,
                        width::Integer, height::Integer)
            # NOTE `interp` can be NULL
            $jfunc(null_or_checked_pointer(interp), handle, width, height)
        end
        function $jfunc(interp::InterpPtr, handle::Tk_PhotoHandle,
                        width::Integer, height::Integer)
            status = $cfunc(interp, handle, width, height)
            status == TCL_OK || unsafe_error(interp, $mesg)
            return nothing
        end
    end
end

unsafe_photo_get_image(img::TkPhoto) = unsafe_photo_get_image(unsafe_find_photo(img))
unsafe_photo_get_image(interp::Union{TclInterp,InterpPtr}, name::Name) =
    unsafe_photo_get_image(unsafe_find_photo(interp, name))
function unsafe_photo_get_image(handle::Tk_PhotoHandle)
    block = Ref{Tk_PhotoImageBlock}()
    Tk_PhotoGetImage(handle, block)
    return block[]
end

function unsafe_photo_put_block(img::TkPhoto,
                                block::Tk_PhotoImageBlock,
                                x::Integer, y::Integer, width::Integer,
                                height::Integer, compRule::Integer)
    unsafe_photo_put_block(img.interp, img.name, block, x, y, width, height, compRule)
end
function unsafe_photo_put_block(interp::Union{TclInterp,InterpPtr}, name::Name,
                                block::Tk_PhotoImageBlock,
                                x::Integer, y::Integer, width::Integer,
                                height::Integer, compRule::Integer)
    handle = unsafe_find_photo(interp, name)
    status = Tk_PhotoPutBlock(interp, handle, Ref(block), x, y, width, height, compRule)
    status == TCL_OK || unsafe_error(interp, "cannot put block in Tk photo")
    return nothing
end

function unsafe_photo_put_zoomed_block(img::TkPhoto,
                                       block::Tk_PhotoImageBlock,
                                       x::Integer, y::Integer,
                                       width::Integer, height::Integer,
                                       zoomX::Integer, zoomY::Integer,
                                       subsampleX::Integer, subsampleY::Integer,
                                       compRule::Integer)
    unsafe_photo_put_zoomed_block(img.interp, img.name, block, x, y, width, height,
                                  zoomX, zoomY, subsampleX, subsampleY, compRule)
end
function unsafe_photo_put_zoomed_block(interp::Union{TclInterp,InterpPtr}, name::Name,
                                       block::Tk_PhotoImageBlock,
                                       x::Integer, y::Integer,
                                       width::Integer, height::Integer,
                                       zoomX::Integer, zoomY::Integer,
                                       subsampleX::Integer, subsampleY::Integer,
                                       compRule::Integer)
    handle = unsafe_find_photo(interp, name)
    status = Tk_PhotoPutZoomedBlock(interp, handle, ref(block), x, y, width, height,
                                    zoomX, zoomY, subsampleX, subsampleY, compRule)
    status == TCL_OK || unsafe_error(interp, "cannot put zoomed block in Tk photo")
    return nothing
end

#-------------------------------------------------------------------------------------------
# Apply a "color" map to an array of gray levels.

struct AffineFunction{Ta,Tb}
    alpha::Ta
    beta::Tb
end
(f::AffineFunction)(x) = f.alpha*x + f.beta

"""
    AffineFunction((a, b) => rng) -> f

Return the affine function that uniformly maps the interval of data values `[a,b]` to the
range of indices `rng`. The range `rng` must not be empty. The affine function is increasing
if `a < b` and decreasing if `a > b`.

The mapping is *safe* in the sense that `round(f(a)) ≥ first(rng)` and `round(f(b)) ≤
last(rng)`.

"""
function AffineFunction(((a,b),rng)::Pair{<:Tuple{<:Any,<:Any},
                                          <:AbstractUnitRange{<:Integer}},
                        rnd::RoundingMode = RoundNearest)
    # Index bounds.
    len = length(rng)::Int
    len > 0 || throw(AssertionError("index range must not be empty"))
    imin = Int(first(rng))::Int
    imax = Int( last(rng))::Int

    # Make sure `a` and `b` have the same type.
    a, b = promote(a, b)

    # Infer the precision for computations, using at least single precision.
    P = get_precision(Float32, typeof(a))

    # Compute affine transform that approximately maps `[a,b]` to `[imin-1/2:imax+1/2]`.
    two = P(2)
    rho = one(P) - eps(P) # reduction factor
    alpha = rho*len/(b - a)
    if isfinite(alpha)
        while true
            beta = ((imin - alpha*a) + (imax - alpha*b))/two
            round(alpha*a + beta, rnd) ≥ imin && round(alpha*b + beta, rnd) ≤ imax && break
            alpha *= rho
        end
    else
        alpha = zero(alpha) # preserve precision and units
        beta = imin/two + imax/two
    end
    get_precision(alpha) == P || throw(AssertionError(
        "expected precision `$(P)` for `alpha`, got `$(get_precision(alpha))`"))
    get_precision(beta) == P || throw(AssertionError(
        "expected precision `$(P)` for `beta`, got `$(get_precision(beta))`"))
    return AffineFunction(alpha, beta)
end
