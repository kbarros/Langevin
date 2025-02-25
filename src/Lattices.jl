module Lattices

using LinearAlgebra
using Langevin.Geometries: Geometry, monkhorst_pack_mesh, calc_site_pos!

export Lattice
export loc_to_cell, loc_to_site, site_to_site
export translationally_equivalent_sets
export calc_neighbor_table, sort_neighbor_table!
export site_to_site_vec!, site_to_site_vec

"""
Represents a finite lattice.
"""
struct Lattice{T<:AbstractFloat}

    "Number of unit cells in direction of first lattice vector."
    L1::Int

    "Number of unit cells in direction of second lattice vector."
    L2::Int

    "Number of unit cells in direction of third lattice vector."
    L3::Int

    "Dimensions of lattice in vector form: [L1,L2,L3]"
    dims::Vector{Int}

    "Number of dimensions lattice lives in."
    ndim::Int

    "Number of orbitals per unit cell in lattice."
    norbits::Int

    "Number of sites in lattice."
    nsites::Int

    "Number of unit cells in lattice."
    ncells::Int

    "Location of each unit cell in lattice."
    cell_loc::Matrix{Int}

    "Position vectors of each site in lattice."
    positions::Matrix{T}

    "k-points associated with finite lattice."
    kpoints::Matrix{T}

    "Records orbital type of each site in lattice."
    site_to_orbit::Vector{Int}

    "Records which unit cell each site live in."
    site_to_cell::Vector{Int}

    #######################
    ## INNER CONSTRUCTOR ##
    #######################
    """
        Lattice(geom::Geometry,L1::Int,L2::Int,L3::Int)::Lattice

    Constructor for Lattice type.
    """
    function Lattice(geom::Geometry{T},L1::Int,L2::Int,L3::Int)::Lattice where {T<:AbstractFloat}

        # making sure dimensions of lattice are valid
        @assert (L1>=1 && L2>=1 && L3>=1)

        # dimensions of lattice
        dims = [L1,L2,L3]

        # getting number of dimensions lattice lives in
        ndim = geom.ndim

        # getting number of orbits per unit cell
        norbits = geom.norbits

        # number of unit cell in lattice
        ncells = L1*L2*L3

        # calculating number of sites in lattice
        nsites = ncells*norbits

        # calculating k-points associated with finite lattice
        kpoints = monkhorst_pack_mesh(geom,L1,L2,L3)

        # allocating array to contain unit cell locations
        cell_loc = Matrix{Int}(undef,3,ncells)

        # allocating array to contain real space position vector of every site in lattice
        positions = Matrix{T}(undef,3,nsites)

        # allcoating array that maps site to orbit in lattice
        site_to_orbit = Vector{Int}(undef,nsites)

        # allocating array that maps site to unit cell in lattice
        site_to_cell = Vector{Int}(undef,nsites)

        # filling in allocated arrays
        site = 1 # keeps track to site number
        cell = 1 # keeps track of unit cell number

        # iterating over unit cells in lattice
        for l3=0:L3-1
            for l2=0:L2-1
                for l1=0:L1-1
                    # recording location of unit cell in lattice
                    cell_loc[1,cell] = l1
                    cell_loc[2,cell] = l2
                    cell_loc[3,cell] = l3
                    # iterating over orbitals in unit cell
                    for orbit=1:norbits
                        # recording the orbit and unit cell associated with site in lattice
                        site_to_orbit[site] = orbit
                        site_to_cell[site] = cell
                        # recording position vector of site in lattice 
                        pos = @view positions[:,site]
                        calc_site_pos!(pos,geom,orbit,l1,l2,l3)
                        site += 1
                    end
                    cell += 1
                end
            end
        end

        return new{T}(L1,L2,L3,dims,ndim,norbits,nsites,ncells,cell_loc,positions,kpoints,site_to_orbit,site_to_cell)
    end

end

########################
## OUTER CONSTRUCTORS ##
########################

function Lattice(geom::Geometry,L1::Int,L2::Int)::Lattice

    @assert geom.ndim==2
    return Lattice(geom,L1,L2,1)
end

function Lattice(geom::Geometry,L1::Int)::Lattice

    L2 = 1
    L3 = 1
    if geom.ndim==2
        L2 = L1
    elseif geom.ndim > 2
        L2 = L1
        L3 = L1
    end
    return Lattice(geom,L1,L2,L3)
end


############################################
## DEFINING METHODS THAT USE LATTICE TYPE ##
############################################

# Defining pretty-print functionality
function Base.show(io::IO, lattice::Lattice)

    printstyled("Lattice{",typeof(lattice.positions[1,1]),"}\n";bold=true)
    print('\n')
    println("•ndim = ", lattice.ndim)
    println("•norbits = ", lattice.norbits)
    println("•ncells = ", lattice.ncells)
    println("•nsites = ", lattice.nsites)
    println("•dims = [L1, L2, L3] = ",lattice.dims)
    print('\n')
    println("•site_to_orbit: ", typeof(lattice.site_to_orbit),size(lattice.site_to_orbit))
    println("•site_to_cell: ", typeof(lattice.site_to_cell),size(lattice.site_to_cell))
    print('\n')
    println("•cell_loc =")
    show(IOContext(stdout, :limit => true), "text/plain", lattice.cell_loc)
    print('\n')
    print('\n')
    println("•positions =")
    show(IOContext(stdout, :limit => true), "text/plain", lattice.positions)
    print('\n')
    print('\n')
    println("•kpoints =")
    show(IOContext(stdout, :limit => true), "text/plain", lattice.kpoints)

end


"""
    loc_to_cell(lattice::Lattice,loc::AbstractVector{Int})::Int

Given a location of a cell in a lattice, return the corresponding cell.
"""
function loc_to_cell(lattice::Lattice,loc::AbstractVector{Int})::Int

    _pbc!(loc,lattice)
    return loc[1] + loc[2]*lattice.L1 + loc[3]*lattice.L1*lattice.L2 + 1
end


"""
    loc_to_site(lattice::Lattice,loc::AbstractVector{Int},orbit::Int)::Int

Given the location of a site in the lattice, return the correpsonding site.
"""
function loc_to_site(lattice::Lattice,loc::AbstractVector{Int},orbit::Int)::Int

    return lattice.norbits * (loc_to_cell(lattice,loc)-1) + orbit
end


"""
    site_to_site(lattice::Lattice,isite::Int,displacement::AbstractVector{Int},orbit::Int)::Int

Get the new site following a displacement from an initial site.
"""
function site_to_site(lattice::Lattice,isite::Int,displacement::AbstractVector{Int},orbit::Int)::Int

    @assert length(displacement)==3
    # getting location of the unit cell that the initial site lives in
    loc = lattice.cell_loc[ : , lattice.site_to_cell[isite] ]
    # displacing the location of the unit cell
    loc += displacement
    # calculating the final site location after the displacement
    return loc_to_site(lattice, loc, orbit)
end

"""
Constructs translationally equivalent sets of sites in lattice.
The translationally equivalent sets are stored in 7-dimensional array
of size ( 2 x numorbits x L1 x L2 x L3 x norbits x norbits ) where
numorbits is the number of sites of a given orbital type in lattice
i.e. numorbits=nsites/norbits.
"""
function translationally_equivalent_sets(lattice::Lattice)::Array{Int,7}
    
    # getting info about lattice
    L1      = lattice.L1
    L2      = lattice.L2
    L3      = lattice.L3
    nsites  = lattice.nsites
    norbits = lattice.norbits
    
    # number of orbitals of a given type in lattice.
    # this is also equal to the number of translationally equivalent pairs of sites
    # in a given translationally equivlent set.
    numorbits = div(nsites,norbits)
    
    # declaring 7 dimensional array to contain translationally equivalent pairs of sites
    sets = zeros(Int, 2, numorbits, L1, L2, L3, norbits, norbits)
    
    # counter for tracking numbers of paired sites in translationally equivalent set
    setcount = 0
    
    # stores second sites in a pairs of sites
    site2 = 0
    
    # to store displacement in unit cells
    displacement = zeros(Int,3)
    
    # iterating over all possible combinations of orbitals
    for orbit1 in 1:norbits
        for orbit2 in 1:norbits
            # iterating over all possible unit cell displacements
            for l3 in 0:L3-1
                for l2 in 0:L2-1
                    for l1 in 0:L1-1
                        # reseting counter for tracking numbers of paired sites in set
                        setcount = 0
                        # iterating over sites in lattice of orbital type orbit1
                        for site1 in orbit1:norbits:nsites
                            # incrementing size of set count
                            setcount += 1
                            # setting displacement in unit cells
                            displacement[1] = l1
                            displacement[2] = l2
                            displacement[3] = l3
                            # getting site2 based on displacement vector away from site1
                            site2 = site_to_site(lattice,site1,displacement,orbit2)
                            # recording pair of sites
                            sets[1,setcount,l1+1,l2+1,l3+1,orbit2,orbit1] = site1
                            sets[2,setcount,l1+1,l2+1,l3+1,orbit2,orbit1] = site2
                        end
                    end
                end
            end
        end
    end
    
    return sets
end


"""
    calc_neighbor_table(lattice::Lattice,orbit1::Int,orbit2::Int,displacement::AbstractVector{Int})::Array{Int,2}

Construct the neighbor table for a certain type of displacement in the lattice.
"""
function calc_neighbor_table(lattice::Lattice,orbit1::Int,orbit2::Int,displacement::AbstractVector{Int})::Matrix{Int}

    # ensuring valid rule is specified for defining neighbor relations
    @assert length(displacement)==3
    @assert (1<=orbit1<=lattice.norbits && 1<=orbit2<=lattice.norbits)

    # total number of neighbor_table
    N = div(lattice.nsites,lattice.norbits)

    # allocating neighbor table array
    neighbor_table = Matrix{Int}(undef,2,N)

    # keeps track of the number of neighbor relations that have been calcualted.
    neighbor_count = 1

    # only iterates over those sites that are an orbit of type orbit1
    for isite in orbit1:lattice.norbits:lattice.nsites
        # get final site
        fsite = site_to_site(lattice,isite,displacement,orbit2)
        # record neighbor_table
        neighbor_table[1,neighbor_count] = isite
        neighbor_table[2,neighbor_count] = fsite
        neighbor_count += 1
    end

    return neighbor_table
end


"""
    sort_neighbor_table!(neighbor_table::AbstractMatrix{Int})::Vector{Int}

Sorts a neighbor table so that the first row is in strictly ascending order,
and for fixed values in the first row, the second row is also in ascending order.
Also returns the sorted permutation order of the neighbor_table based on the original ordering
of the neighbor_table before sorting occured.
"""
function sort_neighbor_table!(neighbor_table::AbstractMatrix{Int})::Vector{Int}

    # making sure dimensions of neighbor table are valid
    @assert size(neighbor_table,1)==2

    # getting the number of neighbor_table
    nneighbor_table = size(neighbor_table,2)

    # filling in array that will contain sorted neighbor relations.
    # note that the third row will contain the sorted permutation order
    # or the original neighbor table.
    sorted_neighbor_table = Matrix{Int}(undef,3,nneighbor_table)
    for i in 1:nneighbor_table
        sorted_neighbor_table[1,i] = neighbor_table[1,i]
        sorted_neighbor_table[2,i] = neighbor_table[2,i]
        sorted_neighbor_table[3,i] = i
        # making sure smaller site in neighbor pair is always in first column
        if sorted_neighbor_table[1,i]>sorted_neighbor_table[2,i]
            sorted_neighbor_table[1,i], sorted_neighbor_table[2,i] = sorted_neighbor_table[2,i], sorted_neighbor_table[1,i]
        end
    end

    # sorting the neighbor_table
    sorted_neighbor_table .= sortslices(sorted_neighbor_table,dims=2)

    # recording sorted neighbor relations
    neighbor_table .= @view sorted_neighbor_table[1:2,:]

    # returning the sorted permuation order based on original ordering of neighbor table
    return sorted_neighbor_table[3,:]
end

"""
    site_to_site_vec!(vector::AbstractVector{Float64},lattice::Lattice,geom::Geometry,site1::Int,site2::Int)

Calculates the displacement vector between two sites in the lattice accounting for periodic boundary conditions.
"""
function site_to_site_vec!(vector::AbstractVector{T},lattice::Lattice{T},geom::Geometry{T},site1::Int,site2::Int) where {T<:AbstractFloat}

    # iterating over each lattice vector direction
    delta = 0 # shift in unit cells
    for direction in 1:3
        # displacement in unit cells
        delta = _cell_displacement(lattice,site1,site2,direction)
        # updating displacement vector
        @. vector += delta * geom.lvecs[:,direction]
    end
    # accounting for basis vector positions of intial and final orbitals
    @. vector += geom.bvecs[:,lattice.site_to_orbit[site1]] - geom.bvecs[:,lattice.site_to_orbit[site2]]
    return nothing
end

function site_to_site_vec(lattice::Lattice{T},geom::Geometry{T},site1::Int,site2::Int)::Vector{T} where {T<:AbstractFloat}

    vector = zeros(T,3)
    site_to_site_vec!(vector,lattice,geom,site1,site2)
    return vector
end


############################################################
## PRIVATE FUNCTIONS NOT TO BE CALLED OUTSIDE THIS MODULE ##
############################################################

"""
    _pbc!(loc::AbstractVector{Int},lattice::Lattice)

Applies periodic boundary conditions.
"""
function _pbc!(loc::AbstractVector{Int},lattice::Lattice)

    @. loc = (loc+lattice.dims)%lattice.dims
    return nothing
end


"""
    _cell_displacement(lattice::Lattice,site1::Int,site2::Int,direction::Int)::Int

Calculates a displacement in unit cells between two sites in the lattice
in the 'direction' of a specified lattice vector, accounting for peridic 
boundary conditions.
"""
function _cell_displacement(lattice::Lattice,site1::Int,site2::Int,direction::Int)::Int

    @assert 1<=direction<=3
    # width of lattice in unit cells in direction of specified lattice vector
    L = lattice.dims[direction]
    # half-width of lattice in unit cells in direction of specified lattice vector
    Lhalf = div(L,2)
    # unit cell that each site lives in
    cell1 = lattice.site_to_cell[site1]
    cell2 = lattice.site_to_cell[site2]
    # displacement in unit cells
    delta = lattice.cell_loc[direction,cell2] - lattice.cell_loc[direction,cell1]
    # accounting for periodic boundary conditions
    if delta > Lhalf
        delta -= L
    elseif delta < -Lhalf
        delta += L
    end
    
    return delta
end

end