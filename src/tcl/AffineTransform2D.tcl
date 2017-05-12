#
# AffineTransforms2D.tcl --
#
# Implementation of 2D affine transforms in Tcl.
#
#------------------------------------------------------------------------------
#
# Copyright (C) 2017, Éric Thiébaut <eric.thiebaut@univ-lyon1.fr>
#
# This file is free software; as a special exception the author gives unlimited
# permission to copy and/or distribute it, with or without modifications, as
# long as this notice is preserved.
#
# This software is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY, to the extent permitted by law; without even the implied
# warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
#------------------------------------------------------------------------------
#
# Affine 2D Transforms
# ====================
#
# An affine 2D transform `A` is defined by 6 real coefficients, `A0`, `A1`,
# `A2`, `A3`, `A4` and `A5`.  Such a transform maps `(x,y)` as `(xp,yp)` given
# by:
#
#     xp = A0*x + A1*y + A2
#     yp = A3*x + A4*y + A5
#
#
# A Tcl list of 6 items is used to store an affine 2D transform
# `A`, it can be created by:
#
#     set A [::AffineTransform2D::new]; # yields the identity
#     set A [::AffineTransform2D::new $A0 $A1 $A2 $A3 $A4 $A5]
#
#
# Many operations are available to manage or apply affine transforms.  The most
# used is:
#
#     set xp_yp [::AffineTransform2D::apply $A $x $y]
#
# yields a list of two transformed coordinates.  Two transforms can be
# combined:
#
#     set C [::AffineTransform2D::combine $A $B]
#
# yields `C` which applies `B` then `A`.  Affine linear transforms can be
# translated:
#
#     set B [::AffineTransform2D::leftTranslate $tx $ty $A]
#     set C [::AffineTransform2D::rightTranslate $A $tx $ty]
#
# yield `B` which applies `A` and then translates by `(tx,ty)` and `C` which
# translates by `(tx,ty)` and then applies `A`.  Affine linear transforms can
# be rotated:
#
#     set B [::AffineTransform2D::leftRotate $theta $A]
#     set C [::AffineTransform2D::rightRotate $A $theta]
#
# yield `B` which applies `A` and then rotates by `theta` and `C` which rotates
# by `theta` and then applies `A`.  Affine linear transforms can be scaled:
#
#     set B [::AffineTransform2D::leftScale $rho $A]
#     set C [::AffineTransform2D::rightScale $A $rho]
#
# yield `B` which applies `A` and then scales by `rho` and `C` which scales by
# `rho` and then applies `A`.  Affine linear transforms can be inverted and
# divided:
#
#     set M [::AffineTransform2D::invert $A]
#     set R [::AffineTransform2D::leftDivide $A $B]
#     set S [::AffineTransform2D::rightDivide $A $B]
#
# yield `M = A^{-1}`, `R = A\B` and `S = A/B`.
#
# The determinant and Jacobian can be computed by:
#
#    ::AffineTransform2D::determinant $A
#    ::AffineTransform2D::jacobian $A
#
# The coordinates of the intercept which is the point `(x,y)` such that
# `A*(x,y) = (0,0)` can be computed by:
#
#    ::AffineTransform2D::intercept $A
#
namespace eval ::AffineTransform2D {
    #
    # `new` yields the identity, while `new $A0 $A1 $A2 $A3 $A4 $A5` yields
    # a new 2D affine transform.
    #
    proc new args {
        set argc [llength $args]
        if {$argc == 0} {
            return [list 1.0 0.0 0.0 0.0 1.0 0.0 0.0]
        } elseif {$argc == 6 && ! [catch {
            set A0 [expr {double([lindex $args 0])}]
            set A1 [expr {double([lindex $args 1])}]
            set A2 [expr {double([lindex $args 2])}]
            set A3 [expr {double([lindex $args 3])}]
            set A4 [expr {double([lindex $args 4])}]
            set A5 [expr {double([lindex $args 5])}]
        }]} {
            return [list $A0 $A1 $A2 $A3 $A4 $A5]
        } else {
            error "expecting 0 or 6 real numbers"
        }
    }

    #
    # `apply $A $x $y` yields the result of applying the transform `A` to
    # coordinates `(x,y)`.
    #
    proc apply {A x y} {
        list \
            [expr {[lindex $A 0]*$x + [lindex $A 1]*$y + [lindex $A 2]}] \
            [expr {[lindex $A 3]*$x + [lindex $A 4]*$y + [lindex $A 5]}]
    }

    # Combine a translation with an affine transform.

    #
    # Left-translating results in translating the output of the transform.
    #
    proc leftTranslate {x y A} {
        list \
            [lindex $A 0] [lindex $A 1] [expr {[lindex $A 2] + $x}] \
            [lindex $A 3] [lindex $A 4] [expr {[lindex $A 5] + $y}]
    }

    #
    # Right-translating results in translating the input of the transform.
    #
    proc rightTranslate {A x y} {
        list \
            [lindex $A 0] \
            [lindex $A 1] \
            [expr {[lindex $A 0]*$x + [lindex $A 1]*$y + [lindex $A 2]}] \
            [lindex $A 3] \
            [lindex $A 4] \
            [expr {[lindex $A 3]*$x + [lindex $A 4]*$y + [lindex $A 5]}]
    }

    #---------------------------------------------------------------------------
    # Scaling an affine transform
    #
    # There are two ways to combine a scaling by a factor `ρ` with an affine
    # transform `A`.  Left-scaling as in:
    #
    #     B = scale(ρ, A)
    #
    # results in scaling the output of the transform; while right-scaling as in:
    #
    #     C = scale(A, ρ)
    #
    # results in scaling the input of the transform.  The above examples yield
    # transforms which behave as:
    #
    #     B*t = ρ*(A*t) = ρ*A(t)
    #     C*t = A*(ρ*t) = A(ρ*t)
    #
    # where `t` is any 2-element tuple.
    #
    proc leftScale {rho A} {
        list \
            [expr {$rho*[lindex $A 0]}] \
            [expr {$rho*[lindex $A 1]}] \
            [expr {$rho*[lindex $A 2]}] \
            [expr {$rho*[lindex $A 3]}] \
            [expr {$rho*[lindex $A 4]}] \
            [expr {$rho*[lindex $A 5]}]
    }

    proc rightScale {A rho} {
        list \
            [expr {$rho*[lindex $A 0]}] \
            [expr {$rho*[lindex $A 1]}] \
            [lindex $A 2] \
            [expr {$rho*[lindex $A 3]}] \
            [expr {$rho*[lindex $A 4]}] \
            [lindex $A 5]
    }

    #---------------------------------------------------------------------------
    #
    # Rotating an affine transform
    #
    # There are two ways to combine a rotation by angle `θ` (in radians
    # counterclockwise) with an affine transform `A`.  Left-rotating as in:
    #
    #     B = rotate(θ, A)
    #
    # results in rotating the output of the transform; while right-rotating as
    # in:
    #
    #     C = rotate(A, θ)
    #
    # results in rotating the input of the transform.  The above examples are
    # similar to:
    #
    #     B = R*A
    #     C = A*R
    #
    # where `R` implements rotation by angle `θ` around `(0,0)`.
    #
    proc leftRotate {theta A} {
        set A0 [lindex $A 0]; set A1 [lindex $A 1]; set A2 [lindex $A 2]
        set A3 [lindex $A 3]; set A4 [lindex $A 4]; set A5 [lindex $A 5]
        set cs [expr {cos($theta)}]
        set sn [expr {sin($theta)}]
        list \
            [expr {$A0*$cs - $A3*$sn}] \
            [expr {$A1*$cs - $A4*$sn}] \
            [expr {$A2*$cs - $A5*$sn}] \
            [expr {$A3*$cs + $A0*$sn}] \
            [expr {$A4*$cs + $A1*$sn}] \
            [expr {$A5*$cs + $A2*$sn}]
    }

    proc rightRotate {A theta} {
        set A0 [lindex $A 0]; set A1 [lindex $A 1]
        set A3 [lindex $A 3]; set A4 [lindex $A 4]
        set cs [expr {cos($theta)}]
        set sn [expr {sin($theta)}]
        list \
            [expr {$A0*$cs + $A1*$sn}] \
            [expr {$A1*$cs - $A0*$sn}] \
            [lindex $A 2] \
            [expr {$A3*$cs + $A4*$sn}] \
            [expr {$A4*$cs - $A3*$sn}] \
            [lindex $A 5]
    }

    #---------------------------------------------------------------------------
    #
    # `determinant $A` yields the determinant of the linear part of the affine
    # transform `A`.
    #
    proc determinant A {
        [expr {[lindex $A 0]*[lindex $A 4] - [lindex $A 1]*[lindex $A 3]}]
    }

    #
    # `jacobian $A` yields the Jacobian of the affine transform `A`, that is
    # the absolute value of the determinant of its linear part.
    #
    proc jacobian A {
        [expr {abs([lindex $A 0]*[lindex $A 4] - [lindex $A 1]*[lindex $A 3])}]
    }

    #
    # `invert $A` yields the inverse of the affine transform `A`.
    #
    proc invert A {
        set A0 [lindex $A 0]; set A1 [lindex $A 1]; set A2 [lindex $A 2]
        set A3 [lindex $A 3]; set A4 [lindex $A 4]; set A5 [lindex $A 5]
        if {[set d [expr {$A0*$A4 - $A1*$A3}]] == 0} {
            error "transformation is not invertible"
        }
        set T0 [expr { $A4/$d}]
        set T1 [expr {-$A1/$d}]
        set T3 [expr {-$A3/$d}]
        set T4 [expr { $A0/$d}]
        list \
            $T0 $T1 [expr {-$T0*$A2 - $T1*$A5}] \
            $T3 $T4 [expr {-$T3*$A2 - $T4*$A5}]
    }

    #
    # `combine $A $B` yields `A*B`, the affine transform which combines the two
    # affine transforms `A` and `B`, that is the affine transform which applies
    # `B` and then `A`.
    #
    proc combine {A B} {
        set A0 [lindex $A 0]; set A1 [lindex $A 1]; set A2 [lindex $A 2]
        set A3 [lindex $A 3]; set A4 [lindex $A 4]; set A5 [lindex $A 5]
        set B0 [lindex $B 0]; set B1 [lindex $B 1]; set B2 [lindex $B 2]
        set B3 [lindex $B 3]; set B4 [lindex $B 4]; set B5 [lindex $B 5]
        list \
            [expr {$A0*$B0 + $A1*$B3}] \
            [expr {$A0*$B1 + $A1*$B4}] \
            [expr {$A0*$B2 + $A1*$B5 + $A2}] \
            [expr {$A3*$B0 + $A4*$B3}] \
            [expr {$A3*$B1 + $A4*$B4}] \
            [expr {$A3*$B2 + $A4*$B5 + $A5}]
    }

    #
    # `rightDivide $A $B` yields `A/B`, the right division of the affine
    # transform `A` by the affine transform `B`.
    #
    proc rightDivide {A B} {
        set B0 [lindex $B 0]; set B1 [lindex $B 1]; set B2 [lindex $B 2]
        set B3 [lindex $B 3]; set B4 [lindex $B 4]; set B5 [lindex $B 5]
        if {[set d [expr {$B0*$B4 - $B1*$B3}]] == 0} {
            error "right operand is not invertible"
        }
        set A0 [lindex $A 0]; set A1 [lindex $A 1]; set A2 [lindex $A 2]
        set A3 [lindex $A 3]; set A4 [lindex $A 4]; set A5 [lindex $A 5]
        set R0 [expr {($A0*$B4 - $A1*$B3)/$d}]
        set R1 [expr {($A1*$B0 - $A0*$B1)/$d}]
        set R3 [expr {($A3*$B4 - $A4*$B3)/$d}]
        set R4 [expr {($A4*$B0 - $A3*$B1)/$d}]
        list \
            $R0 $R1 [expr {$A2 - ($R0*$B2 + $R1*$B5)}] \
            $R3 $R4 [expr {$A5 - ($R3*$B5 + $R4*$B5)}]
    }

    #
    # `leftDivide $A $B` yields `A\\B`, the left division of the affine
    # transform `A` by the affine transform `B`.
    #
    proc leftDivide {A B} {
        set A0 [lindex $A 0]; set A1 [lindex $A 1]; set A2 [lindex $A 2]
        set A3 [lindex $A 3]; set A4 [lindex $A 4]; set A5 [lindex $A 5]
        if {[set d [expr {$A0*$A4 - $A1*$A3}]] == 0} {
            error "left operand is not invertible"
        }
        set B0 [lindex $B 0]; set B1 [lindex $B 1]; set B2 [lindex $B 2]
        set B3 [lindex $B 3]; set B4 [lindex $B 4]; set B5 [lindex $B 5]
        set T0 [expr { $A4/$d}]
        set T1 [expr {-$A1/$d}]
        set T2 [expr {$B2 - $A2}]
        set T3 [expr {-$A3/$d}]
        set T4 [expr { $A0/$d}]
        set T5 [expr {$B5 - $A5}]
        list \
            [expr {$T0*$B0 + $T1*$B3}] \
            [expr {$T0*$B1 + $T1*$B4}] \
            [expr {$T0*$T2 + $T1*$T5}] \
            [expr {$T3*$B0 + $T4*$B3}] \
            [expr {$T3*$B1 + $T4*$B4}] \
            [expr {$T3*$T2 + $T4*$T5}]
    }

    #
    # `intercept $A` yields the coordinates `(x,y)` such that `A(x,y) = (0,0)`.
    #
    proc intercept A {
        set A0 [lindex $A 0]; set A1 [lindex $A 1]; set A2 [lindex $A 2]
        set A3 [lindex $A 3]; set A4 [lindex $A 4]; set A5 [lindex $A 5]
        if {[set d [expr {$A0*$A4 - $A1*$A3}]] == 0} {
            error "transformation is not invertible"
        }
        list \
            [expr {($A1*$A5 - $A4*$A2)/$d}] \
            [expr {($A3*$A2 - $A0*$A5)/$d}]
    }

    proc show args {
        set argc [llength $args]
        if {$argc == 1} {
            set o "stdout"
            set A [lindex $args 0]
        } elseif {$argc == 2} {
            set o [lindex $args 0]
            set A [lindex $args 1]
        } else {
            error "expecting one or two arguments"
        }
        set A0 [lindex $A 0]; set A1 [lindex $A 1]; set A2 [lindex $A 2]
        set A3 [lindex $A 3]; set A4 [lindex $A 4]; set A5 [lindex $A 5]
        puts $o "AffineTransform2D:"
        puts $o "  $A0  $A1  |  $A2"
        puts $o "  $A3  $A4  |  $A5"
    }

    proc runtests {} {
        set B [new 1 0 -3 0.1 1 +2]
        show $B
        puts ""
        set A [invert $B]
        show $A
        puts ""
        set C [combine $A $B]
        show $C
        puts ""
        show [rightTranslate $B 1 4]
        puts ""
        set xy [intercept $B]
        set xpyp [apply $B [lindex $xy 0] [lindex $xy 1]]
        puts "$xy --> $xpyp"
    }
}
