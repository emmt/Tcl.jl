module TclBaseTests

using Tcl
using Test

# We need some irrational constants.
const π = MathConstants.π
const φ = MathConstants.φ

@testset "Utilities" begin
    @test @inferred(Bool, Tcl.bool(true)) === true
    @test @inferred(Bool, Tcl.bool(false)) === false
    @test @inferred(Bool, Tcl.bool("0")) === false
    @test @inferred(Bool, Tcl.bool("0.0")) === false
    @test @inferred(Bool, Tcl.bool(0)) === false
    @test @inferred(Bool, Tcl.bool(0x00)) === false
    @test @inferred(Bool, Tcl.bool(0//1)) === false
    @test @inferred(Bool, Tcl.bool(0.0)) === false
    @test @inferred(Bool, Tcl.bool(-0.0)) === false
    @test @inferred(Bool, Tcl.bool(1)) === true
    @test @inferred(Bool, Tcl.bool(-1234)) === true
    @test @inferred(Bool, Tcl.bool(π)) === true
    @test @inferred(Bool, Tcl.bool(Inf)) === true
    @test @inferred(Bool, Tcl.bool("1")) === true
    @test @inferred(Bool, Tcl.bool("4.2")) === true
    @test @inferred(Bool, Tcl.bool(:true)) === true
    @test @inferred(Bool, Tcl.bool(:True)) === true
    @test @inferred(Bool, Tcl.bool(:TRUE)) === true
    @test @inferred(Bool, Tcl.bool(:yes)) === true
    @test @inferred(Bool, Tcl.bool(:Yes)) === true
    @test @inferred(Bool, Tcl.bool(:YES)) === true
    @test @inferred(Bool, Tcl.bool(:on)) === true
    @test @inferred(Bool, Tcl.bool(:On)) === true
    @test @inferred(Bool, Tcl.bool(:ON)) === true
    @test @inferred(Bool, Tcl.bool(:false)) === false
    @test @inferred(Bool, Tcl.bool(:False)) === false
    @test @inferred(Bool, Tcl.bool(:FALSE)) === false
    @test @inferred(Bool, Tcl.bool(:no)) === false
    @test @inferred(Bool, Tcl.bool(:No)) === false
    @test @inferred(Bool, Tcl.bool(:NO)) === false
    @test @inferred(Bool, Tcl.bool(:off)) === false
    @test @inferred(Bool, Tcl.bool(:Off)) === false
    @test @inferred(Bool, Tcl.bool(:OFF)) === false
    @test_throws ArgumentError Tcl.bool("")
    @test_throws ArgumentError Tcl.bool("oui")
    @test_throws ArgumentError Tcl.bool("maybe")
    @test @inferred(Bool, Tcl.bool(TclObj(true))) === true
    @test @inferred(Bool, Tcl.bool(TclObj(false))) === false
end

@testset "Tcl Objects" begin
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
        if x isa Integer
            @test y.type ∈ (:int, :wideInt)
        else
            @test y.type == :double
        end
        if T == Bool
            @test (@inferred Bool convert(Bool, y)) == !iszero(x)
        elseif T <: Integer
            if !(x isa Integer)
                # Floating-point to non-Boolean integer is not allowed by Tcl.
                @test_throws TclError convert(T, y)
            else
                S = (isconcretetype(T) ? T : Tcl.WideInt)
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
end

@testset "Tcl Variables" begin
    # Get default interpreter.
    interp = @inferred TclInterp()

    for (name, value) in (("a", 42), ("1", 1), ("", "empty"),
                          ("π", π), ("world is beautiful!", true))

        # First unset variable.
        @inferred TclStatus Tcl.exec(TclStatus, "array", "unset", name)
        key = Symbol(name)

        # Set variable.
        @inferred Nothing Tcl.setvar(name, value)

        # Get variable.
        T = typeof(value)
        obj = @inferred TclObj Tcl.getvar(name)
        @test @inferred(TclObj, interp[name]) == obj
        @test @inferred(TclObj, interp[key]) == obj
        if value isa Union{String,Integer}
            @test @inferred(T, Tcl.getvar(T, name)) == value
            @test @inferred(T, interp[T, name]) == value
        elseif value isa AbstractFloat
            @test @inferred(T, Tcl.getvar(T, name)) ≈ value
            @test @inferred(T, interp[T, name]) ≈ value
        end

        # Test existence and delete variable.
        @test Tcl.exists(name)
        @test haskey(interp, name)
        @test haskey(interp, key)
        Tcl.unsetvar(name)
        @test !Tcl.exists(name)
        @test !haskey(interp, name)
        @test !haskey(interp, key)

        # Delete with `delete!`.
        interp[name] = value
        @test haskey(interp, name)
        delete!(interp, name)
        @test !haskey(interp, name)

        # Delete with `unset`.
        interp[name] = value
        @test haskey(interp, name)
        interp[name] = unset
        @test !haskey(interp, name)

    end

    for (part1, part2, value) in (("a", "i", 42),
                                  ("1", "2", 12),
                                  ("", "", "really empty"),
                                  ("π", "φ", π),
                                  ("world is", "beautiful!", true))
        # First unset variable.
        Tcl.unsetvar(part1, nocomplain=true)
        @test_throws TclError Tcl.unsetvar(part1)
        key1 = Symbol(part1)
        key2 = Symbol(part2)

        # Set variable.
        @inferred Nothing Tcl.setvar(part1, part2, value)
        T = typeof(value)
        obj = @inferred TclObj Tcl.getvar(part1, part2)
        @test @inferred(TclObj, interp[part1, part2]) == obj
        @test @inferred(TclObj, interp[key1, key2]) == obj
        @test @inferred(TclObj, interp["$(part1)($(part2))"]) == obj
        if value isa Union{String,Integer}
            @test @inferred(T, Tcl.getvar(T, part1, part2)) == value
            @test @inferred(T, interp[T, part1, part2]) == value
        elseif value isa AbstractFloat
            @test @inferred(T, Tcl.getvar(T, part1, part2)) ≈ value
            @test @inferred(T, interp[T, part1, part2]) ≈ value
        end

        # Test existence and delete variable.
        @test Tcl.exists(part1, part2)
        @test haskey(interp, part1, part2)
        @test haskey(interp, key1, key2)
        Tcl.unsetvar(part1, part2)
        @test !Tcl.exists(part1, part2)
        @test !haskey(interp, part1, part2)
        @test !haskey(interp, key1, key2)

        # Delete with `delete!`.
        interp[part1, part2] = value
        @test haskey(interp, part1, part2)
        delete!(interp, part1, part2)
        @test !haskey(interp, part1, part2)

        # Delete with `unset`.
        interp[part1, part2] = value
        @test haskey(interp, part1, part2)
        interp[part1, part2] = unset
        @test !haskey(interp, part1, part2)
    end

end

@testset "Tcl Lists" begin
    # NULL object pointer yields empty list.
    objc, objv = @inferred Tcl.Private.unsafe_get_list_elements(Ptr{Tcl.Private.Tcl_Obj}(0))
    @test objc === 0
    @test objv === Ptr{Ptr{Tcl.Private.Tcl_Obj}}(0)

    # Tcl "list".
    wa = ("", 1, "hello world!", (true, false), -3.75, π)
    wf = (1, "hello", "world!", true, false, -3.75, π) # "concat" version
    wb = @inferred TclObj Tcl.list(wa...)
    wc = @inferred TclObj TclObj(wa)
    @test wb.type == :list
    @test wc.type == :list
    @test @inferred(length(wb)) == length(wa)
    @test @inferred(length(wc)) == length(wa)
    @test wb == wc
    @test all(wb .== wc)
    @test all([wb[i] == TclObj(wa[i]) for i in 1:length(wa)])
    @test all([wc[i] == TclObj(wa[i]) for i in 1:length(wa)])
    @test wb[4].type == :list
    @test wc[4].type == :list
    @test wb[4][1] == TclObj(wa[4][1])
    @test wc[4][2] == TclObj(wa[4][2])

    # Out of range index yield "missing".
    @test wb[0] === missing
    @test wb[length(wb)+1] === missing

    # Set index in list.
    wb[1] = 3
    wb[3] = wc[4]
    @test @inferred(TclObj, wb[1]) == TclObj(3)
    @test @inferred(TclObj, wb[3]) == @inferred(TclObj, wc[4])

    # Tcl "concat".
    wd = @inferred TclObj Tcl.concat(wa...)
    @test wd.type == :list
    @test @inferred(length(wd)) == length(wf)
    @test all([wd[i] == TclObj(wf[i]) for i in 1:length(wf)])

    # List to vectors.
    t = (-1:3...,)
    o = @inferred TclObj TclObj(t)
    v = @inferred Vector{Int16} convert(Vector{Int16}, o)
    @test Tuple(v) == t
    v = @inferred Vector{String} convert(Vector{String}, o)
    @test Tuple(v) == map(string, t)

    #
    #lst5 = Tcl.list(π, 1, "hello", 2:6)
    #@test length(lst5) == 4
    #@test lst5[1] ≈ π
    #@test lst5[2] == 1
    #@test lst5[3] == "hello"
    #@test all(lst5[4] .== 2:6)
    #push!(lst5, sqrt(2))
    #@test length(lst5) == 5
    #@test lst5[end] ≈ sqrt(2)
    #@test all(lst5[4:end][1] .== 2:6)
    #@test lst5[0] == nothing
    #@test lst5[end+1] == nothing
    #A = lst5[[1 2; 3 4; 5 6]]
    #@test size(A) == (3, 2)
    #@test A[1,1] == lst5[1]
    #@test A[1,2] == lst5[2]
    #@test A[2,1] == lst5[3]
    #@test A[2,2] == lst5[4]
    #@test A[3,1] == lst5[5]
    #@test A[3,2] == lst5[6]

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
#=

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

    =#

end # module
