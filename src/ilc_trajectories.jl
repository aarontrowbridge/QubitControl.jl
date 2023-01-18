module ILCTrajectories

export Traj
export TimeSlice
export add_component!
export times


"""
We define the following struct to store and organize the various components of a trajectory. (e.g. the state `x`, control `u`, and control derivative `du` and `ddu`)

```julia
mutable struct Traj
    data::AbstractMatrix{Float64}
    datavec::AbstractVector{Float64}
    T::Int
    dt::Float64
    dynamical_dts::Bool
    dim::Int
    dims::NamedTuple{dnames, <:Tuple{Vararg{Int}}} where dnames
    bounds::NamedTuple{bnames, <:Tuple{Vararg{AbstractVector{Float64}}}} where bnames
    initial::NamedTuple{inames, <:Tuple{Vararg{AbstractVector{Float64}}}} where inames
    final::NamedTuple{fnames, <:Tuple{Vararg{AbstractVector{Float64}}}} where fnames
    components::NamedTuple{names, <:Tuple{Vararg{AbstractVector{Int}}}} where names
    controls_names::Tuple{Vararg{Symbol}}
end
```

"""
mutable struct Traj
    data::AbstractMatrix{Float64}
    datavec::AbstractVector{Float64}
    T::Int
    dt::Float64
    dynamical_dts::Bool
    dim::Int
    dims::NamedTuple{dnames, <:Tuple{Vararg{Int}}} where dnames
    bounds::NamedTuple{bnames, <:Tuple{Vararg{AbstractVector{Float64}}}} where bnames
    initial::NamedTuple{inames, <:Tuple{Vararg{AbstractVector{Float64}}}} where inames
    final::NamedTuple{fnames, <:Tuple{Vararg{AbstractVector{Float64}}}} where fnames
    components::NamedTuple{names, <:Tuple{Vararg{AbstractVector{Int}}}} where names
    controls_names::Tuple{Vararg{Symbol}}
end


function Traj(
    comp_data::NamedTuple{names, <:Tuple{Vararg{vals}}} where
        {names, vals <: AbstractVecOrMat{Float64}};
    dt::Union{Nothing, Float64}=nothing,
    dynamical_dts=false,
    controls::Union{Symbol, Tuple{Vararg{Symbol}}}=(),
    bounds=(;),
    initial=(;),
    final=(;)
)
    controls = (controls isa Symbol) ? (controls,) : controls

    @assert !isempty(controls)
    @assert !isnothing(dt)

    @assert all([k ∈ keys(comp_data) for k ∈ controls])
    @assert all([k ∈ keys(comp_data) for k ∈ keys(initial)])
    @assert all([k ∈ keys(comp_data) for k ∈ keys(final)])

    @assert all([k ∈ keys(comp_data) for k ∈ keys(bounds)])
    @assert all([(bound isa AbstractVector{Float64}) for bound ∈ bounds])

    comp_data_pairs = []

    for (key, val) ∈ pairs(comp_data)
        if val isa AbstractVector{Float64}
            data = reshape(val, 1, :)
            push!(comp_data_pairs, key => data)
        else
            push!(comp_data_pairs, key => val)
        end
    end

    data = vcat([val for (key, val) ∈ comp_data_pairs]...)

    T = size(data, 2)

    datavec = vec(data)

    # do this to store data matrix as view of datavec
    data = reshape(view(datavec, :), :, T)

    dim = size(data, 1)

    dims_pairs = [(k => size(v, 1)) for (k, v) ∈ comp_data_pairs]

    dims_tuple = NamedTuple(dims_pairs)

    @assert all([length(bounds[k]) == dims_tuple[k] for k ∈ keys(bounds)])
    @assert all([length(initial[k]) == dims_tuple[k] for k ∈ keys(initial)])
    @assert all([length(final[k]) == dims_tuple[k] for k ∈ keys(final)])

    comp_pairs::Vector{Pair{Symbol, AbstractVector{Int}}} =
        [(dims_pairs[1][1] => 1:dims_pairs[1][2])]

    for (k, dim) in dims_pairs[2:end]
        k_range = comp_pairs[end][2][end] .+ (1:dim)
        push!(comp_pairs, k => k_range)
    end

    # add states and controls to dims

    dim_states = sum([dim for (k, dim) in dims_pairs if k ∉ controls])
    dim_controls = sum([dim for (k, dim) in dims_pairs if k ∈ controls])

    push!(dims_pairs, :states => dim_states)
    push!(dims_pairs, :controls => dim_controls)

    # add states and controls to components

    comp_tuple = NamedTuple(comp_pairs)

    states_comps = vcat([comp_tuple[k] for k ∈ keys(comp_data) if k ∉ controls]...)
    controls_comps = vcat([comp_tuple[k] for k ∈ keys(comp_data) if k ∈ controls]...)

    push!(comp_pairs, :states => states_comps)
    push!(comp_pairs, :controls => controls_comps)


    dims = NamedTuple(dims_pairs)
    comps = NamedTuple(comp_pairs)

    return Traj(
        data,
        datavec,
        T,
        dt,
        dynamical_dts,
        dim,
        dims,
        bounds,
        initial,
        final,
        comps,
        controls
    )
end


function Traj(
    datavec::AbstractVector{Float64},
    T::Int,
    components::NamedTuple{
        names,
        <:Tuple{Vararg{AbstractVector{Int}}}
    } where names;
    dt::Union{Nothing, Float64}=nothing,
    dynamical_dts::Bool=false,
    controls::Union{Symbol, Tuple{Vararg{Symbol}}}=(),
    bounds=(;),
    initial=(;),
    final=(;)
)
    controls = (controls isa Symbol) ? (controls,) : controls

    @assert !isempty(controls) "must specify at least one control"
    @assert !isnothing(dt) "must specify a time step size"

    @assert all([k ∈ keys(components) for k ∈ controls])
    @assert all([k ∈ keys(components) for k ∈ keys(initial)])
    @assert all([k ∈ keys(components) for k ∈ keys(final)])

    @assert all([k ∈ keys(components) for k ∈ keys(bounds)])
    @assert all([
        (bound isa AbstractVector{Float64}) ||
        (bound isa AbstractVector{Tuple{Float64, Float64}})
        for bound ∈ bounds
    ])

    data = reshape(view(datavec, :), :, T)
    dim = size(data, 1)

    @assert all([isa(components[k], AbstractVector{Int}) for k in keys(components)])
    @assert vcat([components[k] for k in keys(components)]...) == 1:dim

    dim_pairs = [(k => length(components[k])) for k in keys(components)]

    dim_states = sum([dim for (k, dim) ∈ dim_pairs if k ∉ controls])
    dim_controls = sum([dim for (k, dim) ∈ dim_pairs if k ∈ controls])

    push!(dim_pairs, :states => dim_states)
    push!(dim_pairs, :controls => dim_controls)

    dims = NamedTuple(dim_pairs)

    @assert all([length(bounds[k]) == dims[k] for k in keys(bounds)])
    @assert all([length(initial[k]) == dims[k] for k in keys(initial)])
    @assert all([length(final[k]) == dims[k] for k in keys(final)])

    return Traj(
        data,
        datavec,
        T,
        dt,
        dynamical_dts,
        dim,
        dims,
        bounds,
        initial,
        final,
        components,
        controls
    )
end

function Traj(
    datavec::AbstractVector{Float64},
    Z::Traj
)
    data = reshape(view(datavec, :), :, Z.T)

    @assert size(data, 1) == Z.dim

    return Traj(
        data,
        datavec,
        Z.T,
        Z.dt,
        Z.dynamical_dts,
        Z.dim,
        Z.dims,
        Z.bounds,
        Z.initial,
        Z.final,
        Z.components,
        Z.controls_names
    )
end

function Traj(
    data::AbstractMatrix{Float64},
    components::NamedTuple{
        names,
        <:Tuple{Vararg{AbstractVector{Int}}}
    } where names;
    kwargs...
)
    T = size(data, 2)
    datavec = vec(data)
    return Traj(datavec, T, components; kwargs...)
end

"""
    size(traj::Traj) = (dim = traj.dim, T = traj.T)
"""
Base.size(traj::Traj) = (dim = traj.dim, T = traj.T)

Base.getindex(traj::Traj, t::Int)::TimeSlice =
    TimeSlice(t, view(traj.data, :, t), traj.components, traj.controls_names)

function Base.getindex(traj::Traj, ts::AbstractVector{Int})::Vector{TimeSlice}
    return [traj[t] for t ∈ ts]
end

Base.getindex(traj::Traj, symb::Symbol) = getproperty(traj, symb)

function Base.getproperty(traj::Traj, symb::Symbol)
    if symb ∈ fieldnames(Traj)
        return getfield(traj, symb)
    else
        indices = traj.components[symb]
        return traj.data[indices, :]
    end
end

function add_component!(
    traj::Traj,
    symb::Symbol,
    vals::AbstractVecOrMat{Float64};
    type=:state
)
    if vals isa AbstractVector
        vals = reshape(vals, 1, traj.T)
    end

    @assert size(vals, 2) == traj.T
    @assert symb ∉ keys(traj.components)
    @assert type ∈ (:state, :control)

    dim = size(vals, 1)

    traj.components = (;
        traj.components...,
        symb => (traj.dim + 1):(traj.dim + dim)
    )
    traj.data = vcat(traj.data, vals)
    traj.datavec = vec(view(traj.data, :, :))
    traj.dim += dim
    dim_dict = Dict(pairs(dims))
    dim_dict[symb] = dim
    if type == :state
        push!(traj.states, symb)
        dim_dict[:x] += dim
    else
        push!(traj.controls, symb)
        dim_dict[:u] += dim
    end
    traj.dims = NamedTuple(dim_dict)
end

struct TimeSlice
    t::Int
    data::AbstractVector{Float64}
    components::NamedTuple{
        names,
        <:Tuple{Vararg{AbstractVector{Int}}}
    } where names
    controls_names::Tuple{Vararg{Symbol}}
end

function Base.getproperty(slice::TimeSlice, symb::Symbol)
    if symb in fieldnames(TimeSlice)
        return getfield(slice, symb)
    else
        indices = slice.components[symb]
        return slice.data[indices]
    end
end

function times(traj::Traj)
    return [0:traj.T-1...] .* traj.dt
end

function Base.:*(α::Float64, traj::Traj)
    return Traj(α * traj.datavec, traj)
end

function Base.:*(traj::Traj, α::Float64)
    return Traj(α * traj.datavec, traj)
end

function Base.:+(traj1::Traj, traj2::Traj)
    @assert traj1.dim == traj2.dim
    @assert traj1.T == traj2.T
    return Traj(traj1.datavec + traj2.datavec, traj1)
end

function Base.:-(traj1::Traj, traj2::Traj)
    @assert traj1.dim == traj2.dim
    @assert traj1.T == traj2.T
    return Traj(traj1.datavec - traj2.datavec, traj1)
end

end
