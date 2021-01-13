module PwDynamicDefinition
using ValidatedNumerics
using ..DynamicDefinition
using ..Contractors
using TaylorSeries: Taylor1

using ..DynamicDefinition: derivative

export PwMap, preim, nbranches, plottable

"""
Dynamic based on a piecewise defined map.

The map is defined as T(x) = Ts[k](x) if x ∈ [endpoints[k], endpoints[k+1]).

We set is_full[k]==true if we can prove/assume that the kth branch is full, i.e., Ts[k](endpoints[k])==0 and Ts[k](endpoints[k+1])==1 or vice versa.
"""
struct PwMap <: Dynamic
	Ts::Array{Function, 1}
	endpoints::Array{Interval, 1}
	is_full
	orientations # these will be filled in automatically, usually
end

Base.show(io::IO, D::PwMap) = print(io, "Piecewise-defined dynamic with $(nbranches(D)) branches")

DynamicDefinition.domain(S::PwMap) = hull(S.endpoints[1], S.endpoints[end])

PwMap(Ts, endpoints) = PwMap(Ts, endpoints, fill(false, length(endpoints)-1))
PwMap(Ts, endpoints, is_full) = PwMap(Ts, map(Interval, endpoints), is_full, [sign(derivative(Ts[i], (endpoints[i]+endpoints[i+1])/2)) for i in 1:length(endpoints)-1])

DynamicDefinition.nbranches(D::PwMap)=length(D.endpoints)-1

DynamicDefinition.is_full_branch(D::PwMap) = all(D.is_full)

function DynamicDefinition.preim(D::PwMap, k, y, ϵ = 1e-15)
	@assert 1 <= k <= nbranches(D)
	domain = hull(D.endpoints[k], D.endpoints[k+1])
	root(x->D.Ts[k](x)-y, domain, ϵ)
end

function DynamicDefinition.plottable(D::PwMap, x)
	for k in nbranches(D)
		domain = hull(D.endpoints[k], D.endpoints[k+1])
		if x in domain
			return D.Ts[k](x)
		end
	end
end

"""
hull of an iterable of intervals
"""
common_hull(S) = interval(minimum(x.lo for x in S), maximum(x.hi for x in S))


# Rather than defining derivatives of a PwMap, we define Taylor1 expansions directly
# and let the generic functions in DynamicDefinition to the work
"""
Function call, and Taylor expansion, of a PwMap.
Note that this ignores discontinuities; users are free to shoot themselves
in the foot and call this on a non-smooth piecewise map. No better solutions for now.
"""
function (D::PwMap)(x::Taylor1)
	fx = fill(∅, x.order+1)
	x_restricted = deepcopy(x)
	for i = 1:length(D.endpoints)-1
		x_restricted[0] = x[0] ∩ hull(D.endpoints[i],D.endpoints[i+1])
		if !isempty(x_restricted[0])
			fx_restricted = D.Ts[i](x_restricted)
			fx = fx .∪ fx_restricted.coeffs
		end
	end
	return Taylor1(fx, x.order)
end

end
