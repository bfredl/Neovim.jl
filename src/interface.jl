# high-level interface and shorthands

export current_window, current_buffer, current_tabpage, current_line, set_current, set_current_line
current_window(c::NvimClient) = get_current_window(c)
current_buffer(c::NvimClient) = get_current_buffer(c)
current_tabpage(c::NvimClient) = get_current_tabpage(c)
current_line(c::NvimClient) = get_current_line(c)

set_current(o::Buffer) = set_current_buffer(o.client, o)
set_current(o::Window) = set_current_window(o.client, o)
set_current(o::Tabpage) = set_current_tabpage(o.client, o)

# array interface for buffer
abstract LineIndex
immutable EndRelIndex <: LineIndex i::Int end
immutable OverflowIndex <: LineIndex i::Int end

abstract LineRange
immutable CappedRange <: LineRange
    start::Int
    stop::Int
end
immutable OverflowRange <: LineRange
    start::Union(Integer, OverflowIndex)
    stop::Union(Integer, OverflowIndex)
end

Base.length(b::Buffer) = line_count(b)
Base.endof(b::Buffer) = EndRelIndex(-1)

-(a::LineIndex, b::Integer) = (a.i - b < 0 ? EndRelIndex : OverflowIndex)(a.i - b)
+(a::LineIndex, b::Integer) = (a.i + b < 0 ? EndRelIndex : OverflowIndex)(a.i + b)
+(a::Integer, b::LineIndex) = (a + b.i < 0 ? EndRelIndex : OverflowIndex)(a + b.i)
+(a::LineIndex, b::LineIndex) = (a.i + b.i < 0 ? EndRelIndex : OverflowIndex)(a.i + b.i)

Base.colon(a::Integer, b::EndRelIndex) =
    a > 0 ? CappedRange(a - 1, b.i) : OverflowRange(OverflowIndex(a), b.i)
Base.colon(a::EndRelIndex, b::Integer) =
    b > 0 ? CappedRange(a.i, b - 1) : OverflowRange(a.i, OverflowIndex(b))
Base.colon(a::EndRelIndex, b::EndRelIndex) = CappedRange(a.i, b.i)

Base.colon(a::Integer, b::OverflowIndex) = OverflowRange(a - 1, b)
Base.colon(a::OverflowIndex, b::Integer) = OverflowRange(a, b - 1)
Base.colon(a::OverflowIndex, b::EndRelIndex) = OverflowRange(a, b.i)
Base.colon(a::EndRelIndex, b::OverflowIndex) = OverflowRange(a.i, b)
Base.colon(a::OverflowIndex, b::OverflowIndex) = OverflowRange(a, b)

Base.getindex(b::Buffer, r::CappedRange) = get_line_slice(b, r.start, r.stop, true, true)
function Base.getindex(b::Buffer, i::Union(Integer, EndRelIndex))
    line = b[i:i]
    length(line) > 0 ? line[1] : ""
end
function Base.getindex{T<:Integer}(b::Buffer, r::UnitRange{T})
    if (r.start > r.stop) Array(ByteString, 0)
    elseif (r.start < 1 || r.stop < 1) throw(BoundsError())
    else b[CappedRange(r.start - 1, r.stop - 1)]
    end
end
Base.getindex(b::Buffer, i::Union(OverflowIndex, OverflowRange)) = throw(BoundsError())

Base.setindex!(b::Buffer, lines::Array, r::CappedRange) =
    set_line_slice(b, r.start, r.stop, true, true, lines)
Base.setindex!(b::Buffer, s::String, i::Integer) = b[i:i] = [s]
Base.setindex!(b::Buffer, s::String, i::EndRelIndex) = b[i:i] = [s]
Base.setindex!(b::Buffer, s::String, r::CappedRange) = b[r] = [s]
function Base.setindex!{T<:Integer}(b::Buffer, s::String, r::UnitRange{T})
    ndests = r.stop - r.start + 1
    ndests <= 0 ? s : b[r] = fill(s, ndests)
end
function Base.setindex!{T<:Integer}(b::Buffer, lines::Array, r::UnitRange{T})
    if (r.start < 1 || r.stop < 1) throw(BoundsError())
    else b[CappedRange(r.start - 1, r.stop - 1)] = lines
    end
end
Base.setindex!(b::Buffer, s::String, i::Union(OverflowIndex, OverflowRange)) = throw(BoundsError())

Base.push!(b::Buffer, items...) = (insert(b, -1, [items...]); b)
Base.append!(b::Buffer, items) = (insert(b, -1, items); b)
Base.unshift!(b::Buffer, items...) = (set_line_slice(b, 0, 0, true, false, [items...]); b)

Base.deleteat!(b::Buffer, i::Integer) = deleteat!(b, i:i)
Base.deleteat!{T<:Integer}(b::Buffer, rng::UnitRange{T}) = (b[rng] = []; b)
