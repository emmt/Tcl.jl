#
# colors.jl -
#
# Methods for Tk colors.
#

gray(c::TkGray{T}) where T = c.gray
red(c::TkColors{T}) where T = c.r
green(c::TkColors{T}) where T = c.g
blue(c::TkColors{T}) where T = c.b
alpha(c::TkColorsWithAlpha{T}) where T = c.a

Base.show(io::IO, ::MIME"text/plain", c::TkGray{T}) where {T} =
    print(io,"TkGray{",T,"}(",gray(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkRGB{T}) where {T} =
    print(io,"TkRGB{",T,"}(",red(c),",",green(c),",",blue(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkBGR{T}) where {T} =
    print(io,"TkRGB{",T,"}(",blue(c),",",green(c),",",red(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkRGBA{T}) where {T} =
    print(io,"TkRGBA{",T,"}(",red(c),",",green(c),",",blue(c),",",alpha(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkBGRA{T}) where {T} =
    print(io,"TkRGBA{",T,"}(",blue(c),",",green(c),",",red(c),",",alpha(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkARGB{T}) where {T} =
    print(io,"TkARGB{",T,"}(",alpha(c),",",red(c),",",green(c),",",blue(c),")")

Base.show(io::IO, ::MIME"text/plain", c::TkABGR{T}) where {T} =
    print(io,"TkARGB{",T,"}(",alpha(c),",",blue(c),",",green(c),",",red(c),")")

# Extend Base.show for passing colors to Tk (the alpha component, if any, is
# ignored).

# Extend `print(io,c::TkColor)` for `show` and `string`.
function Base.print(io::IO, c::TkGray{T}) where {T}
    hex = (T === UInt8 ? hex8 : hex16)
    g = hex(gray(c))
    print(io, "#", g, g, g)
end

function Base.print(io::IO, c::TkColor{T}) where {T}
    hex = (T === UInt8 ? hex8 : hex16)
    print(io, "#", hex(red(c)), hex(green(c)), hex(blue(c)))
end

function Base.string(c::TkGray{T}) where {T}
    hex = (T === UInt8 ? hex8 : hex16)
    g = hex(gray(c))
    return *("#", g, g, g)
end

function Base.string(c::TkColor{T}) where {T}
    hex = (T === UInt8 ? hex8 : hex16)
    return *("#", hex(red(c)), hex(green(c)), hex(blue(c)))
end

Base.show(io::IO, c::TkColor) = print(io, c)

TclObj(c::TkColor) = TclObj(string(c))
Base.convert(::Type{TclObj}, c::TkColor) = TclObj(c)::TclObj

hex(x::UInt8)  = string(x; base=16, pad=2)
hex(x::UInt16) = string(x; base=16, pad=4)
hex(x::UInt32) = string(x; base=16, pad=8)
hex(x::UInt64) = string(x; base=16, pad=16)

# FIXME round to nearest value, maybe use FixedPointNumbers
hex8(x::UInt8) = hex(x)
hex8(x::UInt16) = hex((x >>  8)%UInt8)
hex8(x::UInt32) = hex((x >> 24)%UInt8)
hex8(x::UInt64) = hex((x >> 56)%UInt8)

hex16(x::UInt8) = hex((x % UInt16) << 8)
hex16(x::UInt16) = hex(x)
hex16(x::UInt32) = hex((x >> 16)%UInt16)
hex16(x::UInt64) = hex((x >> 48)%UInt16)

TkRGB(s::AbstractString) = TkRGB{UInt8}(s)

function TkRGB{T}(s::AbstractString) where {T<:Unsigned}
    if startswith(s, '#')
        len = length(s) - 1 # number of hexadecimal digits
        if len ∈ (3, 6, 9, 12)
            off = (len÷3) - 1 # offset to end of values
            r1 = nextind(s, firstindex(s)) # skip hash character
            r2 = nextind(s, r1, off)
            g1 = nextind(s, r2, 1)
            g2 = nextind(s, g1, off)
            b1 = nextind(s, g2, 1)
            b2 = nextind(s, b1, off)
            rs = SubString(s, r1:r2)
            gs = SubString(s, g1:g2)
            bs = SubString(s, b1:b2)
            nbits = 4*(off + 1)
            if nbits > 8*sizeof(T)
                # Reduce the precision. TODO Round to nearest.
                n = nbits - 8*sizeof(T)
                if nbits ≤ 32
                    r = (parse(UInt32, rs, base=16) >> n) % T
                    g = (parse(UInt32, gs, base=16) >> n) % T
                    b = (parse(UInt32, bs, base=16) >> n) % T
                else
                    r = (parse(UInt64, rs, base=16) >> n) % T
                    g = (parse(UInt64, gs, base=16) >> n) % T
                    b = (parse(UInt64, bs, base=16) >> n) % T
                end
            else
                # Right pad with zeros.
                n = 8*sizeof(T) - nbits
                r = parse(T, rs, base=16) << n
                g = parse(T, gs, base=16) << n
                b = parse(T, bs, base=16) << n
            end
            return TkRGB{T}(r, g, b)
        end
    else
        rgb = get(Colors.color_names, lowercase(s), nothing)
        if rgb isa Tuple
            s = 8*(sizeof(T) - 1)
            return TkRGB{T}(map(x -> (x % T) << s, rgb)...)
        end
    end
    argument_error("invalid color: `$s`")
end
