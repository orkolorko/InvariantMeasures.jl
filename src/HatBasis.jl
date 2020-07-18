module HatBasis
"""
Hat basis on the Torus [0,1]
"""

using ..BasisDefinition, ..Mod1DynamicDefinition, ..DynamicDefinition
using ValidatedNumerics

export Hat, HatFunction, HatFunctionOnTorus, IntervalOnTorus, EquispacedPartition

"""
Equispaced partition of size n of [0,1]
"""
struct EquispacedPartition{T} <: AbstractVector{T}
	n::Integer
end
function Base.getindex(p::EquispacedPartition{T}, i::Int) where {T}
	@boundscheck 1 <= i <= p.n || throw(BoundsError(p, i))
	return convert(T, i-1) / p.n
end
EquispacedPartition(i::Int) = @error "The real type must be specified explicitly"

Base.size(p::EquispacedPartition) = (p.n,)
Base.IndexStyle(::Type{<:EquispacedPartition}) = IndexLinear()
Base.issorted(p::EquispacedPartition) = true

# TODO: specialize searchsortedfirst, searchsortedlast

struct Hat{T<:AbstractVector} <:Basis
	p::T
	# TODO: check in constructor that p is sorted and starts with 0
end

"""
Return the size of the Hat basis
"""
Base.length(b::Hat) = length(b.p)

"""
Hat function (on the reals)

This is a piecewise linear function such that:
	f(x) = 0 if x <= lo
	f(mi) = 1
	f(hi)
"""
struct HatFunction{T<: Number}
	lo::T
	mi::T
	hi::T
	function HatFunction{T}(lo, mi, hi) where T <: Number
		@assert lo <= mi <= hi
		new{T}(lo, mi, hi)
	end
end
HatFunction(lo::T, mi::T, hi::T) where {T<: Number} = HatFunction{T}(lo,mi,hi);
HatFunction(lo::Number, mi::Number, hi::Number) = HatFunction(promote(lo,mi,hi)...)

"""
Evaluate a HatFunction (on the real line).

Must work correctly when S is an interval.
"""
function (f::HatFunction{T})(x::S) where T where S <: Number
	lo = convert(S, f.lo)
	mi = convert(S, f.mi)
	hi = convert(S, f.hi)

	left_branch = (x-lo)/(mi-lo)
	right_branch = (hi-x)/(hi-mi)
	# 1 is not necessary in practice, but it avoids spurious results from rounding
	return max(min(left_branch, right_branch, 1), 0)
end

"""
A separate type for intervals on the torus (mod 1) to "remind" us of the quotient

The interval is normalized in the constructor: the caller may assume that
* 0 <= i.lo < 1
* i.hi < i.lo + 1 OR i==Interval(0,1)
"""
struct IntervalOnTorus{T <: Real}
	I::Interval{T}
	function IntervalOnTorus{T}(I::Interval) where T<:Real
		# Note that this test may "expand" intervals such as 1e-30..1, to 0..1, but it is not a big issue anyway
		if diam(I) >= 1.
			new{T}(0..1)
		else
			# Note that I - floor(I.lo) may return something smaller than zero in some rounding modes
			new{T}(max(I - floor(I.lo), 0))
		end
	end
end
IntervalOnTorus(I::Interval{T}) where {T} = IntervalOnTorus{T}(I)

"""
Hat function (on the torus)

This is a piecewise linear function such that:
	f(x) = 0 if x <= lo
	f(mi) = 1
	f(x) = 0 if x >= ho
"""
struct HatFunctionOnTorus{T<: Number}
	lo::T
	mi::T
	hi::T
	function HatFunctionOnTorus{T}(lo, mi, hi) where T <: Number
		@assert 0 <= lo < 1
		@assert 0 <= mi < 1
		@assert 0 <= hi < 1
		new{T}(lo, mi, hi)
	end
end
HatFunctionOnTorus(lo::T, mi::T, hi::T) where {T<: Number} = HatFunctionOnTorus{T}(lo,mi,hi);
HatFunctionOnTorus(lo::Number, mi::Number, hi::Number) = HatFunctionOnTorus(promote(lo,mi,hi)...)

"""
Evaluate a HatFunctionOnTorus correctly on an IntervalOnTorus

Assumption: this is only called on functions defined on our partition,
so either mi==0, hi==0, or the three values are in increasing order
"""
function (f::HatFunctionOnTorus{T})(x::IntervalOnTorus{T}) where T <: Number
	lo = Interval{T}(f.lo)
	mi = Interval{T}(f.mi)
	hi = Interval{T}(f.hi)
	# Since I is normalized, we only need two "hats": the one centered in mi,
	# and the one centered in mi+1. It is not complicated to check this
	# (one needs to treat mi==0 separately)

	# constructs correct endpoints for the hat centered in mi, also in the edge cases
	if mi == 0
		lo = lo - 1
	end
	if hi == 0
		hi = 1
	end

	I = x.I
	left_branch = (I-lo)/(mi-lo)
	right_branch = (hi-I)/(hi-mi)
	# 1 is not necessary in practice, but it avoids spurious results from rounding
	first_hat = max(min(left_branch, right_branch, 1), 0)

	I = x.I - 1
	left_branch = (I-lo)/(mi-lo)
	right_branch = (hi-I)/(hi-mi)
	# 1 is not necessary in practice, but it avoids spurious results from rounding
	second_hat = max(min(left_branch, right_branch, 1), 0)

	return max(first_hat, second_hat)
end

"""
makes so that B[j] returns a HatFunctionOnTorus with the j-th basis element
"""
function Base.getindex(B::Hat, i::Int)
	n = length(B)
	@boundscheck 1 <= i <= n || throw(BoundsError(B, i))
	return HatFunctionOnTorus(B.p[mod(i-1, 1:n)], B.p[mod(i, 1:n)], B.p[mod(i+1, 1:n)])
end

"""
Return (in an iterator) the pairs (i, (x, T'(x))) where x is a preimage of p[i], which
describe the "dual" L* evaluation(p[i])
"""
function Base.iterate(S::DualComposedWithDynamic{T, Mod1Dynamic}, state = (1, 1)) where T<:Hat
	i, k = state

	if i == length(S.basis)+1
			return nothing
	end

	# remark that this version supposes that for each i there exists a preimage
	# another more specific version should be implemented for maps with
	# incomplete branches

	x = preim(S.dynamic, k, S.basis.p[i], S.ϵ)
	der = der(S.dynamic, x)

	if k == nbranches(S.dynamic)
		return ((i, (x, der)), (i+1, 1))
	else
		return ((i, (x, der)), (i, k+1))
	end
end

"""
Return the range of indices of the elements of the basis whose support intersects
with the interval y.
The range may end with length(B)+1; this must be interpreted "mod length(B)":
it means that it intersects with the hat function peaked in 0 as well
(think for instance y = 0.9999).
"""
function nonzero_on(B::Hat{T}, y::Interval) where T
	# Note that this cannot rely on arithmetic unless it is verified
	lo = max(searchsortedfirst(B.p, y.lo) -1, 1)
	hi = searchsortedfirst(B.p, y.hi)
	if lo == 1 # 1:N+1 does not make sense and becomes 1:N
		hi = min(hi, length(B))
	end
	return (lo, hi)
end

"""
Given a preimage ```y``` of a point ```x```, this iterator returns
```\\phi_j(y)/T'(y) ```
"""
function Base.iterate(S::ProjectDualElement{T}, state = S.j_min) where T <: Hat
	if state == S.j_max+1
		return nothing
	end
	y, der = S.dual_element
	j = state

	return ((j, S.basis[j](y) / der),
		    state+1)
end

evaluate_integral(B::Hat, i, T) = T(i)/length(B)

function Base.iterate(S::AverageZero{Hat}, state = 1)
	n = length(S.basis)
	if state == n
		return nothing
	end
	v = zeros(Float64, n)
	v[1] = 1
	v[state+1]=-1
	return (v, state+1)
end

using RecipesBase

@userplot PlotHat
@recipe function f(h::PlotHat)
	if length(h.args)!= 2 || (typeof(h.args[1])!= Ulam) || !(typeof(h.args[2])<:AbstractVector)
		error("Plot Ulam needs as an input a Ulam Basis and a vector")
	end

	B = h.args[1]
	w = h.args[2]

	seriestype := :path
	collect(B), mid.(w)
end

end