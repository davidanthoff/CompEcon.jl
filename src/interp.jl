# ---------------- #
# Fitting routines #
# ---------------- #

function get_coefs(basis::Basis, bs::BasisStructure{Tensor}, y)
    if any(bs.order[1, :] .!= 0)
        error("invalid basis structure - first elements must be order 0")
    end
    to_kron = bs.vals[1, :]  # 68
    ckronxi(to_kron, y, ndims(basis):-1:1)  # 66
end

# convert to expanded and call the method below
get_coefs(basis::Basis, bs::BasisStructure{Direct}, y) =
    get_coefs(basis, convert(Expanded, bs), y)

get_coefs(basis::Basis, bs::BasisStructure{Expanded}, y) = bs.vals[1] \ y

# common checks to be run at the top of each funfit
function check_funfit(basis::Basis, x, y)
    m = size(y, 1)
    length(basis) > m && error("Can't be more basis funcs than points in y")
    return m
end

# get_coefs(::Basis, ::BasisStructure, ::Array) does almost all the work for
# these methods
function funfitxy(basis::Basis, bs::BasisStructure, y)
    m = check_funfit(basis, bs, y)
    c = get_coefs(basis, bs, y)
    c, bs
end

function funfitxy{T}(basis::Basis, x::Vector{Vector{T}}, y)
    m = check_funfit(basis, x, y)

    # additional checks for cell array
    mm = prod([size(xi, 1) for xi in x])
    mm != m && error("x and y are incompatible")

    # get Tensor form -- most efficient
    bs = BasisStructure(basis, x, 0)

    # get coefs and return
    c = get_coefs(basis, bs, y)
    c, bs
end

function funfitxy(basis::Basis, x, y)
    # check input sizes
    m = check_funfit(basis, x, y)

    # additional check
    size(x, 1) != m && error("x and y are incompatible")

    bs = BasisStructure(basis, x, 0, Direct())
    c = get_coefs(basis, bs, y)
    c, bs
end

function funfitf(basis::Basis, f::Function, args...)
    x = nodes(basis)[1]
    y = f(x, args...)
    funfitxy(basis, x, y)[1]
end

# ---------- #
# Evaluation #
# ---------- #


# funeval wants to evaluate at a matrix. As a stop-gap until I find some
# time, this method makes a scalar x into a 1x1 matrix
funeval(c, basis::Basis, x::Real, order=0) =
    funeval(c, basis, fill(x, 1, 1), order)

# similar to above for vectors (size will be nx1)
funeval(c, basis::Basis, x::Vector, order=0) = funeval(c, basis, x[:, :], order)

# helper method to construct BasisStructure, then pass to one of the three
# below
function funeval(c, basis::Basis, x::Matrix, order=0)
    d = ndims(basis)
    if size(x, 2) != d
        error("x must have d=$(d) columns")  # 62
    end

    if size(order, 2) == 1
        order = order * fill(1, 1, d)  # 65
    end
    # TODO: defaulting to Direct() should really happen via a constructor.
    #       need to do some design work and clean that up
    bs = BasisStructure(basis, x, order, Direct())  # 67

    funeval(c, bs, order)
end

function funeval(c, bs::BasisStructure{Tensor},
                 order::Matrix{Int}=fill(0, 1, size(bs.order, 2)))  # funeval1
    kk, d = size(order)  # 95
    # 98 reverse the order of evaluation: bs(d)xB(d-1)x...xB(1)
    order = flipdim(order+1*(size(bs.vals, 1) * (0:d-1)' - bs.order+1), 2)

    # 99
    nx = prod([size(bs.vals[1, j], 1) for j=1:d])

    f = zeros(nx, size(c, 2), kk)  # 100

    for i=1:kk
        f[:, :, i] = ckronx(bs.vals, c, order[i, :])  # 102
    end
    return squeeze_trail(f)
end

function funeval(c, bs::BasisStructure{Direct},
                 order::Matrix{Int}=fill(0, 1, size(bs.order, 2)))  # funeval2
    kk, d = size(order)  # 95
    # 114 reverse the order of evaluation: B(d)xB(d-1)x...xB(1)
    order = flipdim(order+1*(size(bs.vals, 1) * (0:d-1)' - bs.order+1), 2)

    f = zeros(size(bs.vals[1], 1), size(c, 2), kk)  # 116

    for i=1:kk
        f[:, :, i] = cdprodx(bs.vals, c, order[i, :])  # 118
    end
    return squeeze_trail(f)
end

# TODO: bugs here. Need to find a better way to replicate the `iscell`
#       calls in Matlab because bs.vals is never and Array{Any}
function funeval(c, bs::BasisStructure{Expanded},
                 order::Matrix{Int}=fill(0, 1, size(bs.order, 2)))  # funeval3

    if isempty(order)
        # TODO: if bs is in Expanded form then why would we ever have cell here?
        #       maybe if we are evaluating derivatives also?
        if isa(bs.vals, Vector{Vector{eltype(bs.vals[1])}})
            kk = length(bs.vals)  # 126
            order = 1:kk'  # 127
        else
            kk = 1  # 128
            order = 1  # 129
        end
    else
        kk = size(order, 1)  # 133
    end

    if isa(bs.vals, Vector{Vector{eltype(bs.vals[1])}})
        nx = size(bs.vals[1], 1)
        f = zeros(nx, size(c, 2), kk)
        for i=1:kk
            # 140 determine which element of bs.vals is the desired basis
            ii = Int[]
            for row=1:size(bs.order, 1)
                r = bs.order[row, :]
                if r == order[i, :]
                    push!(ii, row)
                end
            end

            # 141-143
            isempty(ii)  && error("Requested basis matrix is not available")

            length(ii) > 1 &&  warn("redundant request in funeval3")  # 145

            # NOTE: must do even when length[i] == 1 b/c want element of cell
            #       and indexing cell with vector in julia gives cell instead
            #       of the element
            ii = ii[1]  # 146

            f[:, :, i] = bs.vals[ii]*c  #148
         end
     else
        nx = size(bs.vals, 1)  # 151
        f = zeros(nx, size(c, 2), kk)  # 152
        for i=1:kk
            f[:, :, i] = bs.vals[1]*c  # 154
        end
    end

    return squeeze_trail(f)
end

# ------------------------------ #
# Convenience `Interpoland` type #
# ------------------------------- #

immutable Interpoland{T<:FloatingPoint,N,BST<:ABSR}
    basis::Basis{N}               # the basis -- can't change
    coefs::Vector{T}              # coefficients -- might change
    bstruct::BasisStructure{BST}  # BasisStructure at nodes of `b`
end

function Interpoland(basis::Basis, bs::BasisStructure, y)
    c, bs = funfitxy(basis, bs, y)
    Interpoland(basis, c, bs)
end

function Interpoland{T}(basis::Basis, x::Vector{Vector{T}}, y)
    c, bs = funfitxy(basis, x, y)
    Interpoland(basis, c, bs)
end

function Interpoland(basis::Basis, x, y)
    c, bs = funfitxy(basis, x, y)
    Interpoland(basis, c, bs)
end

function Interpoland(basis::Basis, f::Function)
    # TODO: Decide if I want to do this or if I would rather do
    #       x, xd = nodes(basis); y = f(x); Interpoland(basis, xd, y)
    #       to get the BasisStructure in Tensor format (potentially more)
    #       efficient
    x = nodes(basis)[1]
    y = f(x)
    Interpoland(basis, x, y)
end

# let funeval take care of order and such. This just exists to make it so the
# user doesn't have to keep track of the coefficient vector
evaluate(interp::Interpoland, x::Matrix; order=0) =
    funeval(interp.coefs, interp.basis, x, order)

# construct the grid for the user
evaluate(interp::Interpoland, xs::AbstractVector...; order=0) =
    evaluate(interp, gridmake(xs...); order=order)

# now, given a new vector of `y` data we construct a new coefficient vector
function update_coefs!(interp::Interpoland, y::Vector)
    # leverage the BasisStructure we kept around
    c = funfitxy(interp.basis, interp.bstruct, y)[1]
    copy!(interp.c, c)  # update c inplace b/c Interpoland is immutable
end

# similar for a function -- just hand off to above
update_coefs!(interp::Interpoland, f::Vector) =
    update_coefs!(interp, f(nodes(interp.basis)[1]))

# alias update_coefs! to fit!
fit!(interp::Interpoland, y::Vector) = update_coefs!(interp, y)
fit!(interp::Interpoland, f::Function) = update_coefs!(interp, f)

function Base.writemime{T,N,BST<:ABSR}(io::IO, ::MIME"text/plain",
                                       ::Interpoland{T,N,BST})
    print("$N dimensional interpoland with $BST BasisStructure")
end
