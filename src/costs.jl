module Costs

export QuantumCost
export QuantumCostGradient
export QuantumCostHessian

export structure

export geodesic_cost
export pure_real_cost
export real_cost
export infidelity_cost
export quaternionic_cost
export iso_infidelity

using ..Utils
using ..QuantumLogic
using ..QuantumSystems

using LinearAlgebra
using SparseArrays
using Symbolics

#
# cost functions
#


# TODO: renormalize vectors in place of abs
#       ⋅ penalize cost to remain near unit norm
#       ⋅ Σ α * (1 - ψ̃'ψ̃), α = 1e-3


struct QuantumCost
    cs::Vector{Function}
    isodim::Int

    function QuantumCost(
        sys::AbstractSystem,
        cost::Symbol = :infidelity_cost
    )
        if cost == :energy_cost
            cs = [
                ψ̃ⁱ -> eval(cost)(ψ̃ⁱ, sys.H_target)
                    for i = 1:sys.nqstates
            ]
        elseif cost == :neg_entropy_cost
            cs = [ψ̃ⁱ -> eval(cost)(ψ̃ⁱ) for i = 1:sys.nqstates]
        else
            cs = [
                ψ̃ⁱ -> eval(cost)(
                    ψ̃ⁱ,
                    sys.ψ̃goal[slice(i, sys.isodim)]
                ) for i = 1:sys.nqstates
            ]
        end
        return new(cs, sys.isodim)
    end
end

function (qcost::QuantumCost)(ψ̃::AbstractVector)
    cost = 0.0
    for (i, cⁱ) in enumerate(qcost.cs)
        cost += cⁱ(ψ̃[slice(i, qcost.isodim)])
    end
    return cost
end

struct QuantumCostGradient
    ∇cs::Vector{Function}
    isodim::Int

    function QuantumCostGradient(
        cost::QuantumCost;
        simplify=true
    )
        Symbolics.@variables ψ̃[1:cost.isodim]

        ψ̃ = collect(ψ̃)

        ∇cs_symbs = [
            Symbolics.gradient(c(ψ̃), ψ̃; simplify=simplify)
                for c in cost.cs
        ]

        ∇cs_exprs = [
            Symbolics.build_function(∇c, ψ̃)
                for ∇c in ∇cs_symbs
        ]

        ∇cs = [
            eval(∇c_expr[1])
                for ∇c_expr in ∇cs_exprs
        ]

        return new(∇cs, cost.isodim)
    end
end

@views function (∇c::QuantumCostGradient)(
    ψ̃::AbstractVector
)
    ∇ = similar(ψ̃)

    for (i, ∇cⁱ) in enumerate(∇c.∇cs)

        ψ̃ⁱ_slice = slice(i, ∇c.isodim)

        ∇[ψ̃ⁱ_slice] = ∇cⁱ(ψ̃[ψ̃ⁱ_slice])
    end

    return ∇
end

struct QuantumCostHessian
    ∇²cs::Vector{Function}
    ∇²c_structures::Vector{Vector{Tuple{Int, Int}}}
    isodim::Int

    function QuantumCostHessian(
        cost::QuantumCost;
        simplify=true
    )

        Symbolics.@variables ψ̃[1:cost.isodim]
        ψ̃ = collect(ψ̃)

        ∇²c_symbs = [
            Symbolics.sparsehessian(
                c(ψ̃),
                ψ̃;
                simplify=simplify
            ) for c in cost.cs
        ]

        ∇²c_structures = []

        for ∇²c_symb in ∇²c_symbs
            K, J, _ = findnz(∇²c_symb)

            KJ = collect(zip(K, J))

            filter!(((k, j),) -> k ≤ j, KJ)

            push!(∇²c_structures, KJ)
        end

        ∇²c_exprs = [
            Symbolics.build_function(∇²c_symb, ψ̃)
                for ∇²c_symb in ∇²c_symbs
        ]

        ∇²cs = [
            eval(∇²c_expr[1])
                for ∇²c_expr in ∇²c_exprs
        ]

        return new(∇²cs, ∇²c_structures, cost.isodim)
    end
end

function structure(
    H::QuantumCostHessian,
    T::Int,
    vardim::Int
)
    H_structure = []

    T_offset = index(T, 0, vardim)

    for (i, KJⁱ) in enumerate(H.∇²c_structures)

        i_offset = index(i, 0, H.isodim)

        for kj in KJⁱ
            push!(H_structure, (T_offset + i_offset) .+ kj)
        end
    end

    return H_structure
end

@views function (H::QuantumCostHessian)(ψ̃::AbstractVector)

    Hs = []

    for (i, ∇²cⁱ) in enumerate(H.∇²cs)

        ψ̃ⁱ = ψ̃[slice(i, H.isodim)]

        for (k, j) in H.∇²c_structures[i]

            Hⁱᵏʲ = ∇²cⁱ(ψ̃ⁱ)[k, j]

            append!(Hs, Hⁱᵏʲ)
        end
    end

    return Hs
end


#
# primary cost functions
#

function infidelity_cost(
    ψ̃::AbstractVector,
    ψ̃goal::AbstractVector
)
    ψ = iso_to_ket(ψ̃)
    ψgoal = iso_to_ket(ψ̃goal)
    return abs(1 - abs2(ψ'ψgoal))
end

function energy_cost(
    ψ̃::AbstractVector,
    H::AbstractMatrix
)
    ψ = iso_to_ket(ψ̃)
    return real(ψ' * H * ψ)
end


# TODO: figure out a way to implement this without erroring and Von Neumann entropy being always 0 for a pure state
function neg_entropy_cost(
    ψ̃::AbstractVector
)
    ψ = iso_to_ket(ψ̃)
    ρ = ψ * ψ'
    ρ = Hermitian(ρ)
    return tr(ρ * log(ρ))
end




#
# experimental cost functions
#

function pure_real_cost(ψ̃, ψ̃goal)
    ψ = iso_to_ket(ψ̃)
    ψgoal = iso_to_ket(ψ̃goal)
    return -(ψ'ψgoal)
end

function geodesic_cost(ψ̃, ψ̃goal)
    ψ = iso_to_ket(ψ̃)
    ψgoal = iso_to_ket(ψ̃goal)
    amp = ψ'ψgoal
    return min(abs(1 - amp), abs(1 + amp))
end

function real_cost(ψ̃, ψ̃goal)
    ψ = iso_to_ket(ψ̃)
    ψgoal = iso_to_ket(ψ̃goal)
    amp = ψ'ψgoal
    return min(abs(1 - real(amp)), abs(1 + real(amp)))
end

function iso_infidelity(ψ̃, ψ̃f)
    ψ = iso_to_ket(ψ̃)
    ψf = iso_to_ket(ψ̃f)
    return 1 - abs2(ψ'ψf)
end


function quaternionic_cost(ψ̃, ψ̃goal)
    return min(
        abs(1 - dot(ψ̃, ψ̃goal)),
        abs(1 + dot(ψ̃, ψ̃goal))
    )

end

end
