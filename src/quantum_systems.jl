module QuantumSystems

export AbstractQuantumSystem

export QuantumSystem
export TransmonSystem

using ..QuantumLogic

using HDF5

using LinearAlgebra

Im2 = [
    0 -1;
    1  0
]

G(H) = I(2) ⊗ imag(H) - Im2 ⊗ real(H)

abstract type AbstractQuantumSystem end

# TODO: make subtypes: SingleQubitSystem, TwoQubitSystem, TransmonSystem, MultimodeSystem, etc.

struct QuantumSystem <: AbstractQuantumSystem
    n_wfn_states::Int
    n_aug_states::Int
    nstates::Int
    nqstates::Int
    isodim::Int
    augdim::Int
    vardim::Int
    ncontrols::Int
    control_order::Int
    G_drift::Matrix{Float64}
    G_drives::Vector{Matrix{Float64}}
    control_bounds::Vector{Float64}
    ψ̃init::Vector{Float64}
    ψ̃goal::Vector{Float64}
    ∫a::Bool
end


# TODO: move ψinit and ψgoal into prob def

function QuantumSystem(
    H_drift::Matrix,
    H_drive::Union{Matrix{T}, Vector{Matrix{T}}},
    ψinit::Union{Vector{C1}, Vector{Vector{C1}}},
    ψgoal::Union{Vector{C2}, Vector{Vector{C2}}},
    control_bounds::Vector{Float64};
    ∫a=false,
    control_order=2,
    goal_phase=0.0
) where {C1 <: Number, C2 <: Number, T <: Number}

    if isa(ψinit, Vector{C1})
        nqstates = 1
        isodim = 2 * length(ψinit)
        ψ̃init = ket_to_iso(ψinit)
        ψgoal *= exp(im * goal_phase)
        ψ̃goal = ket_to_iso(ψgoal)
    else
        @assert isa(ψgoal, Vector{Vector{C2}})
        nqstates = length(ψinit)
        @assert length(ψgoal) == nqstates
        isodim = 2 * length(ψinit[1])
        ψ̃init = vcat(ket_to_iso.(ψinit)...)
        ψgoal[1] *= exp(im * goal_phase)
        ψ̃goal = vcat(ket_to_iso.(ψgoal)...)
    end

    G_drift = G(H_drift)

    if isa(H_drive, Matrix{T})
        ncontrols = 1
        G_drive = [G(H_drive)]
    else
        ncontrols = length(H_drive)
        G_drive = G.(H_drive)
    end

    @assert length(control_bounds) == length(G_drive)

    augdim = control_order + ∫a

    n_wfn_states = nqstates * isodim
    n_aug_states = ncontrols * augdim

    nstates = n_wfn_states + n_aug_states

    vardim = nstates + ncontrols

    return QuantumSystem(
        n_wfn_states,
        n_aug_states,
        nstates,
        nqstates,
        isodim,
        augdim,
        vardim,
        ncontrols,
        control_order,
        G_drift,
        G_drive,
        control_bounds,
        ψ̃init,
        ψ̃goal,
        ∫a
    )
end

struct TransmonSystem <: AbstractQuantumSystem
    n_wfn_states::Int
    n_aug_states::Int
    nstates::Int
    nqstates::Int
    isodim::Int
    augdim::Int
    vardim::Int
    ncontrols::Int
    control_order::Int
    G_drift::Matrix{Float64}
    G_drives::Vector{Matrix{Float64}}
    ψ̃init::Vector{Float64}
    ψ̃goal::Vector{Float64}
    ∫a::Bool
end










function QuantumSystem(
    hf_path::String;
    return_data=false,
    kwargs...
)
    h5open(hf_path, "r") do hf

        H_drift = hf["H_drift"][:, :]

        H_drives = [
            copy(transpose(hf["H_drives"][:, :, i]))
                for i = 1:size(hf["H_drives"], 3)
        ]

        ψinit = vcat(transpose(hf["psi1"][:, :])...)
        ψgoal = vcat(transpose(hf["psif"][:, :])...)


        qubit_a_bounds = [0.018 * 2π, 0.018 * 2π]
        cavity_a_bounds = fill(0.03, length(H_drives) - 2)
        a_bounds = [qubit_a_bounds; cavity_a_bounds]

        system = QuantumSystem(
            H_drift,
            H_drives,
            ψinit,
            ψgoal,
            a_bounds,
            kwargs...
        )

        if return_data
            data = Dict()
            controls = copy(transpose(hf["controls"][:, :]))
            data["controls"] = controls
            Δt = hf["tlist"][2] - hf["tlist"][1]
            data["Δt"] = Δt
            return system, data
        else
            return system
        end
    end
end

end
