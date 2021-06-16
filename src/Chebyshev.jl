"""
Chebyshev basis on the Interval [0,1]
"""

using ..BasisDefinition, ..Mod1DynamicDefinition, ..DynamicDefinition
using ValidatedNumerics
import ..BasisDefinition: one_vector, integral_covector, is_integral_preserving

struct Chebyshev{T<:AbstractVector} <:Basis
	p::T
	# TODO: check in constructor that p is sorted, starts with 0 and ends with 1
end

#we suppose ValidatedNumerics computes the Chebyshev points with adequate precision
ChebCouples(n, T) = hcat(
	[Interval{T}(pi); (reverse([Interval{T}(0.0); [j*Interval{T}(pi)/n for j in 1:n-1] ]))],
	[Interval{T}(0.0) ; (reverse([Interval{T}(1.0); [cos(j*Interval{T}(pi)/n) for j in 1:n-1]]).+1)/2])

ChebPoints(n, T) = ChebCouples(n, T)[:, 2] 

Chebyshev(n::Integer; T = Float64) = Chebyshev(ChebPoints(n, T))

"""
Return the size of the Chebyshev basis
"""
Base.length(B::Chebyshev) = length(B.p) - 1

"""
Eval the Chebyshev polynomial up to degree n on an array of 
points in [-1, 1].

Not satisfactory, the intervals explode

"""
function _eval_T(n, x::Array{T}) where {T}
	k = length(x)
	M = zeros(T, k, n+1)
	M[:, 1] = ones(k)
	M[:, 2] = x
	for i in 3:n+1
		M[:, i] = (2*x).*M[:, i-1]-M[:, i-2]
	end
	return M
end

""" Eval a polynomial in Chebyshev basis, ClenshawBackward, using ball arithmetic
Following Viviane Ledoux, Guillaume Moroz 
"Evaluation of Chebyshev polynomials on intervals andapplication to root finding"
"""
# TODO: use ErrorFreeArithmetics or FastRounding???
function eval_Clenshaw_Backward(coeff, x::Interval{T}) where {T}
	a, r = midpoint_radius(x)
	n = length(coeff)
	u = zeros(Float64, n+1)
	ϵ = zeros(Float64, n+1)
	u[n] = coeff[n]
	for k in reverse(2:n-1)
		u_temp = Interval{T}(coeff[k])-u[k+2]
		u_temp += 2*a*u[k+1]
		u[k], ϵ[k] = midpoint_radius(u_temp)
	end
	u_temp = Interval{T}(coeff[1])-u[3]
	u_temp += a*u[2]
	u[1], ϵ[1] = midpoint_radius(u_temp)
	
	e = zeros(Float64, n+1)
	for k in reverse(2:n-1)
		e[k] = e[k+1]+2*r*abs(u[k+1])+ϵ[k]
	end
	e[1] = e[2]+r*abs(u[1])+ϵ[1]
	return u[1]+Interval(-e[1], e[1])
end

function Clenshaw(coeff, x::T) where {T<:Real}
	n = length(coeff)
	u = zeros(Float64, n+1)
	u[n] = coeff[n]
	for k in reverse(2:n-1)
		u[k] = coeff[k]+2*x*u[k+1]-u[k+2]
	end
	u[1] = coeff[1]+x*u[2]-u[3]
	return u[1]
end


Clenshaw(coeff, x::Interval{T}) where {T} = eval_Clenshaw_Backward(coeff, x)

# makes so that B[j] returns the (i+1)-th Chebyshev polynomial
# on [0, 1]
"""
Returns a function that computes the values of the (i+1)-th Chebyshev polynomial
on [0, 1]
"""
function Base.getindex(B::Chebyshev, i::Int)
 	n = length(B)
 	@boundscheck 0 <= i <= n || throw(BoundsError(B, i))
 	v = zeros(n+1)
	v[i+1] = 1
	return x-> Clenshaw(v, 2*x-1)
end

struct ChebyshevDual <: Dual
    x::Vector{Interval} #TODO: a more generic type may be needed in future
    xlabel::Vector{Int}
    x′::Vector{Interval}
end

Dual(B::Chebyshev, D, ϵ) = ChebyshevDual(preimages_and_derivatives(B.p, D, 1:length(B.p)-1, ϵ)...)
Base.length(dual::ChebyshevDual) = length(dual.x)
Base.eltype(dual::ChebyshevDual) = Tuple{eltype(dual.xlabel), Tuple{eltype(dual.x), eltype(dual.x′)}}
function iterate(dual::ChebyshevDual, state=1)
    if state <= length(dual.x)
        return ((dual.xlabel[state], (dual.x[state], abs(dual.x′[state]))), state+1)
    else
        return nothing
    end
end

# """
# Return (in an iterator) the pairs (i, (x, |T'(x)|)) where x is a preimage of p[i], which
# describe the "dual" L* evaluation(p[i
# """
# function Base.iterate(S::DualComposedWithDynamic{T, D}, state = (1, 1)) where T<:Hat where D<:Dynamic
# 	@assert is_full_branch(S.dynamic)

# 	i, k = state

# 	if i == length(S.basis)+1
# 			return nothing
# 	end

# 	x = preim(S.dynamic, k, S.basis.p[i], S.ϵ)
# 	absT′ = abs(derivative(S.dynamic, x))

# 	if k == nbranches(S.dynamic)
# 		return ((i, (x, absT′)), (i+1, 1))
# 	else
# 		return ((i, (x, absT′)), (i, k+1))
# 	end
# end

# function BasisDefinition.is_dual_element_empty(::Hat, d)
# 	# TODO: the preim() may indeed be empty, so there could be an additional check here
# 	return false
# end

# BasisDefinition.is_refinement(Bf::Hat, Bc::Hat) = Bc.p ⊆ Bf.p

# function integral_covector(B::Hat)
# 	n = length(B)
# 	return 1/n * ones(Interval{Float64}, n)'
# end

# function one_vector(B::Hat)
# 	return ones(length(B))
# end


# """
# Return the range of indices of the elements of the basis whose support intersects
# with the given dual element (i.e., a pair (y, absT')).
# The range may end with length(B)+1; this must be interpreted "mod length(B)":
# it means that it intersects with the hat function peaked in 0 as well
# (think for instance y = 0.9999).
# """
# function BasisDefinition.nonzero_on(B::Hat, dual_element)
# 	y, absT′ = dual_element
# 	# Note that this cannot rely on arithmetic unless it is verified

# 	y = y ∩ Interval(0.,1.) # we assume it's bona-fide interval in [0,1]
# 	# this should work for preims(), since they are supposed to return
# 	# a number in [0,1]

# 	# finds in which semi-open interval [p[k], p[k+1]) y.lo and y.hi fall
# 	lo = searchsortedlast(B.p, y.lo)
# 	hi = searchsortedlast(B.p, y.hi)
# 	lo = min(lo, length(B)) # lo may be n+1 if y.lo==1
# 	hi = min(hi, length(B)) # hi may be n+1 if y.hi==1
# 	hi = hi + 1 # because the hat centered in p[k] is also nonzero in the interval before

# 	if lo == 1 # 1:N+1 does not make sense and would mean that the first interval is counted twice
# 		hi = min(hi, length(B))
# 	end
# 	return (lo, hi)
# end

# """
# Given a preimage ```y``` of a point ```x```, this iterator returns
# ```\\phi_j(y)/T'(y) ```
# """
# function Base.iterate(S::ProjectDualElement{T,DT}, state = S.j_min) where {T <: Hat,DT}
# 	if state == S.j_max+1
# 		return nothing
# 	end
# 	y, absT′ = S.dual_element
# 	j = state
# 	y_normalized = IntervalOnTorus(y)
# 	n = length(S.basis)

# 	return ((j, S.basis[mod(j, 1:n)](y_normalized) / absT′),
# 		    state+1)
# end

# BasisDefinition.strong_norm(B::Hat) = Lipschitz
# BasisDefinition.weak_norm(B::Hat) = Linf
# BasisDefinition.aux_norm(B::Hat) = L1

# evaluate_integral(B::Hat, i, T) = T(i)/length(B)

# function Base.iterate(S::AverageZero{Hat}, state = 1)
# 	n = length(S.basis)
# 	if state == n
# 		return nothing
# 	end
# 	v = zeros(Float64, n)
# 	v[1] = 1
# 	v[state+1]=-1
# 	return (v, state+1)
# end

# BasisDefinition.weak_projection_error(B::Hat) = 0.5 ⊘₊ Float64(length(B), RoundDown)
# BasisDefinition.aux_normalized_projection_error(B::Hat) = 0.5 ⊘₊ Float64(length(B), RoundDown)
# BasisDefinition.strong_weak_bound(B::Hat) = 2. ⊗₊ Float64(length(B), RoundDown)
# BasisDefinition.aux_weak_bound(B::Hat) = 1.
# BasisDefinition.weak_by_strong_and_aux_bound(B::Hat) = (1., 1.)
# BasisDefinition.bound_weak_norm_from_linalg_norm(B::Hat) = @error "TODO"
# BasisDefinition.bound_linalg_norm_L1_from_weak(B::Hat) = @error "TODO"
# BasisDefinition.bound_linalg_norm_L∞_from_weak(B::Hat) = @error "TODO"

# function BasisDefinition.invariant_measure_strong_norm_bound(B::Hat, D::Dynamic)
# 	A, B = dfly(strong_norm(B), aux_norm(B), D)
# 	@assert A < 1.
# 	return B ⊘₊ (1. ⊖₋ A)
# end


# using RecipesBase

# """
# Plots a function in the Hat basis
# """
# @recipe function f(B::Hat, w::AbstractVector)

# 	legend --> :bottomright

# 	if eltype(w) <: Interval
# 		w = mid.(w)
# 	end

# 	@series begin
# 		seriestype --> :path
# 		label --> L"f_{\delta}"
# 		ylims --> (0, NaN)
# 		B.p, vcat(w, w[end])
# 	end
# end

# """
# Displays error on a function in the Hat basis
# """
# @recipe function f(B::Hat, error::Number, w)

# 	if eltype(w) <: Interval
# 		w = mid.(w)
# 	end

# 	if isfinite(error)
# 		@series begin
# 			seriestype --> :path
# 			seriesalpha --> 0.5
# 			fillrange --> vcat(w, w[end]) .- error
# 			label --> "Error area"
# 			B.p, vcat(w, w[end]) .+ error
# 		end
# 	end
# end