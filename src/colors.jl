#
# colors.jl -
#
# Methods for colors.
#

new_object(c::Colorant) = new_object("#"*hex(RGB(c)))

const GrayRamp = range(colorant"black", colorant"white", length=255)

"""
    colorize(arr, cmap=GrayRamp; kwds...)

Return an array with colors representing the values of the data array `arr`.

`cmap` specifies a vector of colors to colorize valid and in range data values. The default
color map is a ramp of shades of gray.

# Keywords

* `vmin` and `vmax` specify the minimal and maximal data values to colorize.

* `cmin` and `cmax` specify the respective colors for data values less than `vmin` and
  greater than `vmax.

* `cbad` specifies the color of bad values (`NaN`, `missing`, etc.).

"""
colorize(arr::Array{T,N}, cmap::AbstractVector{C}; kwds...) where {T<:Real,N,C} =
    colorize!(Array{C,N}(undef, size(arr)), arr, cmap; kwds...)

function colorize!(dst::Array{C,N}, arr::Array{T,N},
                   cmap::AbstractVector{C};
                   cmin = nothing,
                   cmax = nothing,
                   cbad = nothing,
                   vmin = nothing,
                   vmax = nothing) where {T<:Real,N,C}
    # Supply default values.
    if isnothing(vmin) && isnothing(vmax)
        vmin, vmax = extrema(arr)
    elseif isnothing(vmin)
        vmin = minimum(arr)
        vmax = convert(T, vmax)
    elseif isnothing(vmax)
        vmin = convert(T, vmin)
        vmax = maximum(arr)
    else
        vmin = convert(T, vmin)
        vmax = convert(T, vmax)
    end
    if isnothing(cmin)
        cmin = first(cmap)
    else
        cmin = convert(C, cmin)
    end
    if isnothing(cmax)
        cmax = last(cmap)
    else
        cmax = convert(C, cmax)
    end
    if isnothing(cbad)
        cbad = first(cbad)
    else
        cbad = convert(C, cbad)
    end

    rng = eachindex(IndexLinear(), cmap) # index range
    f = AffineFunction((vmin, vmax) => rng)

    return colorize!(dst, arr, cmap, cmin, cmax, cbad, f)
end

"""
    colorize!(dst, src, cmap, cmin, cmax, cbad, f) -> dst

Colorize `dst` by applying a transfer function `f` to the values of `src` for indexing the
lookup color table `cmap`. Colors `cmin`, `cmax`, and `cbad` are used when `f(x)` is too
small, too large, or invalid (not-a-number).

The methods behaves as:

```julia
@inbounds for i in eachindex(src, dst)
    t = f(src[i])
    dst[i] = if isnan(t)
        cbad
    else
        k = round(t, RoundNearest)
        k < firstindex(cmap) ? cmin :
        k >  lastindex(cmap) ? cmax : cmap[convert(Int, k)]
    end
end
```

"""
function colorize!(dst::Array{C,N}, src::Array{T,N},
                   cmap::AbstractVector{C}, cmin::C, cmax::C, cbad::C,
                   f) where {T,C,N}
    axes(dst) == axes(src) || throw(DimensionMismatch("arrays must have the same axes"))
    unsafe_colorize!(dst, src, cmap, cmin, cmax, cbad, f, Base.promote_op(f, T))
    return dst
end

function unsafe_colorize!(dst::Array{C,N}, src::Array{<:Any,N},
                          cmap::AbstractVector{C}, cmin::C, cmax::C, cbad::C,
                          f, ::Type{T}) where {C,N,T<:Integer}
    kmin = firstindex(cmap)
    kmax = lastindex(cmap)
    tmin = convert(T, kmin)::T
    tmax = convert(T, kmax)::T
    @inbounds for i in eachindex(dst, src)
        t = f(src[i])::T
        dst[i] = if t < tmin
            cmin
        elseif t > tmax
            cmax
        else
            cmap[t]
        end
    end
    return nothing
end

function unsafe_colorize!(dst::Array{C,N}, src::Array{<:Any,N},
                          cmap::AbstractVector{C}, cmin::C, cmax::C, cbad::C,
                          f, ::Type{T}) where {C,N,T<:Union{Float32,Float64,BigFloat}}
    # The value of `round(Int, t, r)` when `t = i ± 1/2` with `i` integer depends on the
    # rounding mode `r`, on the sign and on the parity of `i`. To avoid these odds for
    # enforcing index bounds, we compute upper and lower thresholds, `tmin` and `tmax` with
    # a `guard` value slightly less than `1/2`. This is valid for indices in the range
    # ±2_048 for 16-bit floats, in the range ±16_777_216 for 32-bit floats, etc. In other
    # words, our assumptions are valid for any index `i` such that `i == T(i)` with `T` the
    # floating-point type.
    imin, imax = firstindex(cmap), lastindex(cmap)
    n = max(-imin, imax) # maximum absolute value of indices
    n ≤ max_exact_int(T) || throw(AssertionError(
        "insufficient floating-point precision `$T` for indices in `$imin:$imax`"))
    guard = ((one(T) - eps(T))/2)::T
    tmin = convert(T, imin - guard)::T
    tmax = convert(T, imax + guard)::T
    @inbounds for i in eachindex(dst, src)
        # NOTE For rounding to the nearest integer, `roundnearest` is the fastest,
        #      `RoundNearestTiesUp` is 13% slower, and `RoundNearestTiesAway` is 48% slower
        #      (on my machine).
        t = f(src[i])::T
        dst[i] = if isnan(t)
            cbad
        else
            t = round(t, RoundNearest)
            t < tmin ? cmin :
            t > tmax ? cmax : cmap[convert(Int, t)]
        end
    end
    return nothing
end

# All integers in the ranges `±max_exact_int(T)` can be exactly represented by a value of
# type `T`.
max_exact_int(::Type{T}) where {T<:AbstractFloat} = Int(1) << significant_bits(T)
max_exact_int(::Type{T}) where {T<:Float64} = Int64(1) << significant_bits(T)
max_exact_int(::Type{T}) where {T<:BigFloat} = Int128(1) << significant_bits(T)
max_exact_int(::Type{T}) where {T<:Integer} = typemax(signed(T))

# Number of significant bits in floating-point type.
significant_bits(::Type{Float16}) = 11
significant_bits(::Type{Float32}) = 24
significant_bits(::Type{Float64}) = 53
significant_bits(::Type{BigFloat}) = 63
