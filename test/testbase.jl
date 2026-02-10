module TclBaseTests

using Tcl
using Test

# We need some irrational constants.
const π = MathConstants.π
const φ = MathConstants.φ

@testset "Basic Interface" begin

    @testset "Tcl objects" begin
        script = "puts {hello world!}"
        symbolic_script = Symbol(script)
        x = @inferred TclObj(script)
        @test x isa TclObj
        @test length(propertynames(x)) == 3
        @test hasproperty(x, :ptr)
        @test hasproperty(x, :refcnt)
        @test hasproperty(x, :type)
        @test x.type == :string
        @test isone(x.refcnt)
        @test isreadable(x)
        @test iswritable(x)
        @test x.ptr === @inferred(pointer(x))
        @test script == @inferred string(x)
        @test script == @inferred String(x)
        @test script == @inferred convert(String, x)
        @test x == x
        @test x == script
        @test script == x
        @test x == symbolic_script
        @test symbolic_script == x
        @test isequal(x, x)
        @test isequal(x, script)
        @test isequal(script, x)
        @test isequal(x, symbolic_script)
        @test isequal(symbolic_script, x)

        # copy() yields same but distinct objects
        y = @inferred copy(x)
        @test y isa TclObj
        @test y.type == :string
        @test isone(y.refcnt) && isone(x.refcnt)
        @test y.ptr !== x.ptr
        @test x == y
        @test isequal(x, y)

        # length() converts object into a list
        @test length(y) === 2 # there are 2 tokens in the script
        @test y.type == :list
        @test firstindex(y) === 1
        @test lastindex(y) === length(y)
        @test @inferred(eltype(y)) === TclObj
        @test @inferred(eltype(typeof(y))) === TclObj
        @test y[1] == "puts"
        @test y[2] == "hello world!"

        # `boolean` type.
        x = @inferred TclObj("true")
        @test x.type == :string
        @test @inferred(repr(x)) == "TclObj(\"true\")"
        @test convert(Bool, x) === true
        @test x.type == :boolean
        @test @inferred(repr(x)) == "TclObj(true)"
        x = @inferred TclObj("false")
        @test x.type == :string
        @test @inferred(repr(x)) == "TclObj(\"false\")"
        @test convert(Bool, x) === false
        @test x.type == :boolean
        @test @inferred(repr(x)) == "TclObj(false)"

        # Destroy object and then calling the garbage collector must not throw.
        z = TclObj(0)
        z = 0 # no longer a Tcl object
        @test try GC.gc(); true; catch; false; end

        # Conversions. NOTE Tcl conversion rules are more restricted than Julia.
        # TODO Test unsigned integers.
        values = (true, false, -1, 0x03, Int16(8), Int32(-217),
                  typemin(Int8), typemax(Int8),
                  typemin(Int16), typemax(Int16),
                  typemin(Int32), typemax(Int32),
                  typemin(Int64), typemax(Int64),
                  0.0f0, 1.0, 2//3, π, big(1.3))
        types = (Bool, Int8, Int16, Int32, Int64, Integer, Float32, Float64, AbstractFloat)
        @testset "Conversion of $x::$(typeof(x)) to $T" for x in values, T in types
            y = @inferred TclObj(x)
            @test y.type == (x isa Integer ? :int : :double)
            if T == Bool
                @test (@inferred Bool convert(Bool, y)) == !iszero(x)
            elseif T <: Integer
                if !(x isa Integer)
                    # Floating-point to non-Boolean integer is not allowed by Tcl.
                    @test_throws TclError convert(T, y)
                else
                    S = (T === Integer ? Int : T)
                    if typemin(S) ≤ x ≤ typemax(S)
                        @test (@inferred S convert(T, y)) == convert(S, x)
                    else
                        @test_throws Union{TclError,InexactError} convert(T, y)
                    end
                end
            else # T is non-integer real
                S = (T === AbstractFloat ? Float64 : T)
                @test (@inferred S convert(T, y)) == convert(S, x)
            end
        end

        # Tuples.
        x = @inferred TclObj(:hello)
        @test x.type == :string
        @test x == :hello
        @test x == "hello"
        t = (2, -3, x, 8.0)
        @test x.refcnt == 1
        y = @inferred TclObj(t)
        @test x.refcnt == 2
        @test y.type == :list
        @test length(y) == length(t)
        # TODO @test y == t

        # Get default interpreter.
        interp = @inferred TclInterp()

    end
    #=
    @testset "Variables" begin
        interp = TclInterp()
        for (name, value) in (("a", 42), ("1", 1), ("", "empty"),
                              ("π", π), ("w\0rld is beautiful!", true))
            # Check methods.
            Tcl.exec(TclStatus, "array", "unset", name)
            Tcl.setvar(name, value)
            if typeof(value) <: Union{String,Integer}
                @test Tcl.getvar(name) == value
            elseif typeof(value) <: AbstractFloat
                @test Tcl.getvar(name) ≈ value
            end
            @test Tcl.exists(name)
            Tcl.unsetvar(name)
            @test !Tcl.exists(name)

            # Check indexable interface.
            interp[name] = value
            if typeof(value) <: Union{String,Integer}
                @test interp[name] == value
            elseif typeof(value) <: AbstractFloat
                @test interp[name] ≈ value
            end
            @test Tcl.exists(name)
            interp[name] = nothing
            @test !Tcl.exists(name)
        end

        for (name1, name2, value) in (("a", "i", 42),
                                      ("1", "2", 12),
                                      ("", "", "really empty"),
                                      ("π", "φ", π),
                                      ("w\0rld is", "beautiful!", true))
            # Check methods.
            Tcl.unsetvar(name1, nocomplain=true)
            Tcl.setvar(name1, name2, value)
            if typeof(value) <: Union{String,Integer}
                @test Tcl.getvar(name1, name2) == value
            elseif typeof(value) <: AbstractFloat
                @test Tcl.getvar(name1, name2) ≈ value
            end
            @test Tcl.exists(name1, name2)
            Tcl.unsetvar(name1, name2)
            @test !Tcl.exists(name1, name2)

            # Check indexable interface.
            interp[name1, name2] = value
            if typeof(value) <: Union{String,Integer}
                @test interp[name1, name2] == value
            elseif typeof(value) <: AbstractFloat
                @test interp[name1, name2] ≈ value
            end
            @test Tcl.exists(name1, name2)
            interp[name1, name2] = nothing
            @test !Tcl.exists(name1, name2)
        end
    end

    @testset "Scalars" begin
        var = "x"
        @testset "Integers" begin
            for v in (1, -1, 0, 250, 1<<40)
                x = Tcl.exec(:set, var, v)
                @test x == Tcl.getvar(var)
                @test typeof(x) <: Integer
            end
        end
        @testset "Floats" begin
            for v in (1.0, 0.0, -0.5, π, φ, sqrt(2))
                x = Tcl.exec(:set, var, v)
                @test x == Tcl.getvar(var)
                @test typeof(x) <: Cdouble
            end
        end
        @testset "Strings" begin
            for v in ("", "hellow world!", "1", "true", " ", "\n", "\t", "\r",
                      "\a", "caleçon espiègle")
                x = Tcl.exec(:set, var, v)
                @test x == Tcl.getvar(var)
                @test typeof(x) <: String
            end
            for v in ("\u0", "\u2200", "\u2200 x \u2203 y")
                x = Tcl.exec(:set, var, TclObj(v))
                @test x == Tcl.getvar(var)
                @test typeof(x) <: String
            end
        end
        @testset "Booleans" begin
            for v in (true, false)
                x = Tcl.exec(:set, var, v)
                @test x == Tcl.getvar(var)
                @test typeof(x) <: Integer
            end
        end
    end

    @testset "Lists" begin
        wa = ["", "false", "hello world!", "caleçon espiègle"]
        wb = Tcl.exec(TclObj, "list", wa...)
        wc = Tcl.getvalue(wb)
        @test all(wc .== wa)
        @test eltype(wc) <: String

        xa = [false,true,0,1,2,3]
        xb = Tcl.exec(TclObj, "list", xa...)
        xc = Tcl.getvalue(xb)
        @test all(xc .== xa)
        @test eltype(xc) <: Integer

        ya = [-4,6,-7]
        yb = Tcl.exec(TclObj, "list", ya...)
        yc = Tcl.getvalue(yb)
        @test all(yc .== ya)
        @test eltype(yc) <: Integer

        za = [-1.0, 0.0, 1.0, -4.2, π, sqrt(2), φ]
        zb = Tcl.exec(TclObj, "list", za...)
        zc = Tcl.getvalue(zb)
        @test all(zc .≈ za)
        @test all(zc[1:3] .== za[1:3]) # no loss of precision?
        @test eltype(zc) <: AbstractFloat

        lst1 = Tcl.exec("list",xb,yb)
        @test eltype(lst1) <: Vector{<:Integer}
        @test all(lst1[1] == xa)
        @test all(lst1[2] == ya)

        lst2 = Tcl.exec("list",xb,"hello")
        @test typeof(lst2) == Vector{Any}
        @test all(lst2[1] .== xc)
        @test all(lst2[2] == "hello")

        lst3 = Tcl.exec("list",xb,yb,zb)
        @test typeof(lst3) == Vector{Any}
        @test all(lst3[1] .== xc)
        @test all(lst3[2] .== yc)
        @test all(lst3[3] .== zc)

        lst2b = Tcl.exec(TclObj,"list",xb,"hello")
        lst3b = Tcl.exec(TclObj,"list",xb,yb,zb)
        lst4 = Tcl.exec("list",lst2b,lst3b)
        @test typeof(lst4) == Vector{Any}
        @test length(lst4) == 2
        @test all(lst4[1][1] .== xc)
        @test all(lst4[1][2] == "hello")
        @test all(lst4[2][1] .== xc)
        @test all(lst4[2][2] .== yc)
        @test all(lst4[2][3] .== zc)

        lst5 = Tcl.list(π, 1, "hello", 2:6)
        @test length(lst5) == 4
        @test lst5[1] ≈ π
        @test lst5[2] == 1
        @test lst5[3] == "hello"
        @test all(lst5[4] .== 2:6)
        push!(lst5, sqrt(2))
        @test length(lst5) == 5
        @test lst5[end] ≈ sqrt(2)
        @test all(lst5[4:end][1] .== 2:6)
        @test lst5[0] == nothing
        @test lst5[end+1] == nothing
        A = lst5[[1 2; 3 4; 5 6]]
        @test size(A) == (3, 2)
        @test A[1,1] == lst5[1]
        @test A[1,2] == lst5[2]
        @test A[2,1] == lst5[3]
        @test A[2,2] == lst5[4]
        @test A[3,1] == lst5[5]
        @test A[3,2] == lst5[6]

        #yc = Tcl.exec("list",x,z)
        #r = Tcl.exec(TclObj,"list",4.6,pi)
        #q = Tcl.exec(TclObj,"list",4,pi)
        #Tcl.exec("list",4,pi)
        #Tcl.exec("list",x,z,r)
        #Tcl.exec("list",x,z,"hello",r)
        #interp = TclInterp()
        #interp[:v] = r
        #Tcl.eval(interp, raw"foreach x $v { puts $x }")

    end
    =#
end

end
