"""
Compute preimages of monotonic sequences
"""

using IntervalArithmetic
using .Contractors

"""
Type used to represent a "branch" of a dynamic. The branch is represented by a monotonic map `f` with domain `X=(a,b)` with a≤b (where typically a,b are intervals). 
`Y=(f(a),f(b))` and `increasing` may be provided (for instance if we know that `Y=(0,1)`), otherwise they are computed automatically.
"""
struct Branch{T,S}
    f::T
    X::Tuple{S, S}
    Y::Tuple{S, S}
    increasing::Bool
end
Branch(f, X, Y=(f(Interval(X[1])), f(Interval(X[2]))), increasing=unique_increasing(Y[1], Y[2])) = Branch{typeof(f), typeof(interval(X[1]))}(f, X, Y, increasing)

"""
Return Branches for a given PwMap, in an iterable.

TODO: in future, maybe it is a better idea to replace the type PwMap directly with an array of branches, since that's all we need
"""
function branches(D::PwMap)
    return [Branch(D.Ts[k], (D.endpoints[k], D.endpoints[k+1]), (D.y_endpoints[k,1], D.y_endpoints[k,2]), D.increasing[k]) for k in 1:length(D.Ts)]
end

"""
Smallest possible i such that a is in the semi-open interval [y[i], y[i+1]).

This should work properly even if `a, y` are intervals; in this case it returns the *smallest* possible value of i over all possible "assignments" of a, y inside those intervals.
Assumes y is sorted, i.e., map(y, x->Interval(x).lo) and map(y, x->Interval(x).hi) are sorted.
"""
function first_overlapping(y, a)
    if iszero(a) # avoids -0 crap
        a = zero(a)
    end
    searchsortedlast(y, Interval(a).lo, by=x->Interval(x).hi)
end

"""
Largest possible j such that a-ε is in the semi-open interval [y[j], y[j+1]).

This should work properly even if `a, y` are intervals; in this case it returns the *largest* possible value of i over all possible "assignments" of a, y inside those intervals.
Assumes y is sorted, i.e., map(y, x->Interval(x).lo) and map(y, x->Interval(x).hi) are sorted.
"""
function last_overlapping(y, a)
    if iszero(a) # avoids -0 crap
        a = zero(a)
    end
    searchsortedfirst(y, Interval(a).hi, by=x->Interval(x).lo) - 1
end

"""
Construct preimages of an increasing array y under a monotonic branch defined on X = (a, b), propagating additional labels `ylabel`

The sequence y subdivides the y-axis into semi-open intervals [y[l], y[l+1]); each of them is identified by the label `ylabel[l]`. We construct an increasing sequence 
x that splits X (in the x-axis) into semi-open intervals, each of them with f([x[k], x[k+1]) ⊂ [y[l], y[l+1]) for a certain l. 
We set xlabel[k] = ylabel[l], and return the pair (x, xlabel).

In the simplest case where D is full-branch, the points in x are preimages of the points in y, but in the general case they can also include D.endpoints:
in general, there may be a certain number of points in y that have no preimage at the beginning and the end of the sequence, because 
they fall out of the range R = [f(a), f(b)]. In the worst case, no point has a preimage, because y[i] < R < y[i+1] for some 
i (or vice versa with orientations), and in this case we just return the 1-element vectors x = [branch.X[1]] and xlabel = [i].

x[begin] always coincides with branch.X[1], while branch.X[2] is "the point after x[end]", and is not stored explicitly in x, for easier composing.
In this way x and xlabel have the same length.

This function fills the array by using a bisection strategy to save computations: if y ∈ [a,b], then f⁻¹(y) ∈ [f⁻¹(a),f⁻¹(b)] (paying attention to orientation).
So we can fill v by filling in first entries `v[k+1]` with higher dyadic valuation of k.

For a dynamic with multiple branches, preimages(y, D) is simply the concatenation of x, xlabel for b in all branches. These values still form an increasing sequence that
splits X into intervals, each of which is mapped into a different semi-open interval [y[k], y[k+1]).
"""
function preimages(y, br::Branch, ylabel = 1:length(y), ϵ = 0.0)

    if br.increasing
        i = first_overlapping(y, br.Y[1])  # smallest possible i such that a is in the semi-open interval [y[i], y[i+1]).
        j = last_overlapping(y, br.Y[2]) # largest possible j such that b-ε is in the semi-open interval [y[j], y[j+1]).
        n = j - i + 1
        x = fill((-∞..∞)::typeof(Interval(br.X[1])), n)
        xlabel = collect(ylabel[i:j]) # we collect to avoid potential type instability, since this may be an UnitRange while in the other branch we could have a StepRange
        x[1] = br.X[1]
        if n == 1
            return (x, xlabel)
        end
        # the bisection strategy: fill the array in "strides" of length `stride`, then halve the stride and repeat
        # for instance, if the array is 1..13 (with x[1] filled in already), we first take stride=8 and fill in x[9],
        # then stride=4 and fill in x[5], x[13], (note that the distance is `2stride`, since x[9], and in general all the even multiples of `stride`, is already filled in)
        # then stride=2 and fill in x[3], x[7], x[11],
        # then stride=1 and fill in x[2], x[4], x[6], x[8], x[10], x[12]
        # at each step we have bracketed the preimage in a "search range" given by already-computed preimages x[k-stride] and x[k+stride].
        stride = prevpow(2, n-1)
        while stride >= 1
            # fill in v[i] using x[i-stride].lo and x[i+stride].hi as range for the preimage search
            for k = 1+stride:2*stride:n
                search_range = Interval(x[k-stride].lo, (k+stride <= n ? x[k+stride] : Interval(br.X[2])).hi)
                x[k] = preimage(y[i-1+k], br.f, search_range, ϵ)
            end
            stride = stride ÷ 2
        end
    else # branch decreasing
        i = last_overlapping(y, br.Y[1]) # largest possible j such that b-ε is in the semi-open interval [y[j], y[j+1]).
        j = first_overlapping(y, br.Y[2]) # smallest possible i such that a is in the semi-open interval [y[i], y[i+1]).
        n = i - j + 1
        x = fill((-∞..∞)::typeof(Interval(br.X[1])), n)
        xlabel = collect(ylabel[i:-1:j])
        x[1] = br.X[1]
        if n == 1
            return (x, xlabel)
        end
        stride = prevpow(2, n-1)
        while stride >= 1
            # fill in v[i] using x[i-stride].lo and x[i+stride].hi as range for the preimage search
            for k = 1+stride:2*stride:n
                search_range = Interval(x[k-stride].lo, (k+stride <= n ? x[k+stride] : Interval(br.X[2])).hi)
                x[k] = preimage(y[i+2-k], br.f, search_range, ϵ)
            end
            stride = stride ÷ 2
        end
    end
    return (x, xlabel)
end

function preimages(y, D::Dynamic, ylabel = 1:length(y), ϵ = 0.0)
    results = collect(preimages(y, b, ylabel, ϵ) for b in branches(D))
    x = vcat((result[1] for result in results)...)
    xlabel = vcat((result[2] for result in results)...)
    return x, xlabel
end

"""
Compute preimages of D *and* the derivatives f'(x) in each point.

Returns: x, xlabel, x′

Assumes that the dynamic is full-branch, because otherwise things may compose the wrong way.
This is not restrictive because we'll need it only for the Hat assembler (at the moment)

We combine them in a single function because there are avenues to optimize by recycling some computations (not completely exploited for now)
"""
function preimages_and_derivatives(y, br::Branch, ylabel = 1:length(y), ϵ = 0.0)
    x, xlabel = preimages(y, br, ylabel, ϵ)
    f′ = Contractors.derivative(br.f)
    x′ = f′.(x)
    return x, xlabel, x′
end
function preimages_and_derivatives(y, D::Dynamic, ylabel = 1:length(y), ϵ = 0.0)
    @assert is_full_branch(D)
    results = collect(preimages_and_derivatives(y, b, ylabel, ϵ) for b in branches(D))
    x = vcat((result[1] for result in results)...)
    xlabel = vcat((result[2] for result in results)...)
    x′ = vcat((result[3] for result in results)...)
    return x, xlabel, x′
end

"""
Composed map D1 ∘ D2 ∘ D3. We store with [D1, D2, D3] in this order.

We overwrite ∘ in base, so one can simply write D1 ∘ D2 or ∘(D1, D2, D3) to construct them.
"""
struct ComposedDynamic <: Dynamic
    dyns::Tuple{Vararg{Dynamic}}
end
Base.:∘(d::Dynamic...) = ComposedDynamic(d)

"""
Utility function to return the domain of a dynamic
"""
domain(D::PwMap) = (D.endpoints[begin], D.endpoints[end])
domain(D::ComposedDynamic) = domain(D.dyns[end])

function preimages(z, Ds::ComposedDynamic, zlabel = 1:length(z), ϵ = 0.0)
    for d in Ds.dyns
        z, zlabel = preimages(z, d, zlabel, ϵ)
    end
    return z, zlabel
end
function preimages_and_derivatives(z, Ds::ComposedDynamic, zlabel = 1:length(z), ϵ = 0.0)
    derivatives = fill(1, 1:length(z))
    for d in Ds.dyns
        z, zindex, z′ = preimages_and_derivatives(z, d, 1:length(z), ϵ)
        zlabel = zlabel[zindex]
        derivatives = derivatives[zindex] .* z′ 
    end
    return z, zlabel, derivatives
end

"""
Replacement of DualComposedWithDynamic.
"""
abstract type Dual end

struct UlamDual <: Dual
    x::Vector{Interval} #TODO: a more generic type may be needed in future
    xlabel::Vector{Int}
    lastpoint::Interval
end
Dual(B::Ulam, D, ϵ) = UlamDual(preimages(B.p, D, 1:length(B.p)-1, ϵ)..., domain(D)[end])

Base.length(dual::UlamDual) = length(dual.x)
Base.eltype(dual::UlamDual) = Tuple{eltype(dual.xlabel), Tuple{eltype(dual.x), eltype(dual.x)}}
function iterate(dual::UlamDual, state = 1)
    n = length(dual.x)
    if state < n
        return (dual.xlabel[state], (dual.x[state], dual.x[state+1])), state+1
    elseif state == n
        return (dual.xlabel[n], (dual.x[n], dual.lastpoint)), state+1
    else
        return nothing
    end
end

struct HatDual <: Dual
    x::Vector{Interval} #TODO: a more generic type may be needed in future
    xlabel::Vector{Int}
    x′::Vector{Interval}
end

Dual(B::Hat, D, ϵ) = HatDual(preimages_and_derivatives(B.p, D, 1:length(B.p)-1, ϵ)...)
Base.length(dual::HatDual) = length(dual.x)
Base.eltype(dual::HatDual) = Tuple{eltype(dual.xlabel), Tuple{eltype(dual.x), eltype(dual.x′)}}
function iterate(dual::HatDual, state=1)
    if state <= length(dual.x)
        return ((dual.xlabel[state], (dual.x[state], abs(dual.x′[state]))), state+1)
    else
        return nothing
    end
end

# Variants of assemble and DiscretizedOperator; the code is repeated here for easier comparison with the older algorithm
function assemble2(B, D, ϵ=0.0; T = Float64)
	I = Int64[]
	J = Int64[]
	nzvals = Interval{T}[]
	n = length(B)

	# TODO: reasonable size hint?

	for (i, dual_element) in Dual(B, D, ϵ)
		if !is_dual_element_empty(B, dual_element)
			for (j, x) in ProjectDualElement(B, dual_element)
				push!(I, i)
				push!(J, mod(j,1:n))
				push!(nzvals, x)
			end
		end
	end

	return sparse(I, J, nzvals, n, n)
end

function DiscretizedOperator2(B, D, ϵ=0.0; T = Float64)
	L = assemble2(B, D, ϵ; T)
	if is_integral_preserving(B)
		return IntegralPreservingDiscretizedOperator(L)
	else
		f = integral_covector(B)
		e = one_vector(B)
		w = f - f*L #will use interval arithmetic when L is an interval matrix
		return NonIntegralPreservingDiscretizedOperator(L, e, w)
	end
end