#
# colors.jl -
#
# Methods for colors.
#

new_object(c::Colorant) = new_object("#"*hex(RGB(c)))
