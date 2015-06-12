# high-level interface and shorthands

export current_window, current_buffer, current_tabpage, current_line, set_current, set_current_line, cursor, cursor!

current_window(c::NvimClient) = get_current_window(c)
current_buffer(c::NvimClient) = get_current_buffer(c)
current_tabpage(c::NvimClient) = get_current_tabpage(c)
current_line(c::NvimClient) = get_current_line(c)

set_current(o::Buffer) = set_current_buffer(o.client, o)
set_current(o::Window) = set_current_window(o.client, o)
set_current(o::Tabpage) = set_current_tabpage(o.client, o)

cursor(o::Window) = ((r,c) = get_cursor(o); (r, c + 1))
cursor!(o::Window, r::Integer, c::Integer) = set_cursor(o, (r, c - 1))

# array interface for buffer

# index relative end ( -1 is last element)
immutable EndRelIndex
    i::Int
end

vimindex(a::Integer) = a > 0 ? a - 1 : throw(BoundsError())
vimindex(a::EndRelIndex) = a.i < 0 ? a.i : throw(BoundsError())

# range where indices already are converted to api indicies
immutable CappedRange
    start::Int
    stop::Int
    CappedRange(a,b) = new(vimindex(a),vimindex(b))
end

Base.length(b::Buffer) = line_count(b)
Base.endof(b::Buffer) = EndRelIndex(-1)

-(a::EndRelIndex, b::Integer) = EndRelIndex(a.i - b)
+(a::EndRelIndex, b::Integer) = EndRelIndex(a.i + b)
+(a::Integer, b::EndRelIndex) = EndRelIndex(a + b.i)

Base.colon(a::Integer, b::EndRelIndex) = CappedRange(a, b)
Base.colon(a::EndRelIndex, b::Union(Integer, EndRelIndex)) = CappedRange(a, b)

Base.getindex(b::Buffer, r::CappedRange) = get_line_slice(b, r.start, r.stop, true, true)
Base.getindex(b::Buffer, ::Colon) = b[1:end]
function Base.getindex(b::Buffer, i::Union(Integer, EndRelIndex))
    line = b[i:i]
    length(line) > 0 ? line[1] : ""
end
function Base.getindex{T<:Integer}(b::Buffer, r::UnitRange{T})
    if (r.start > r.stop)
        Array(ByteString, 0)
    else
        b[CappedRange(r.start, r.stop)]
    end
end

Base.setindex!(b::Buffer, lines::Array, r::CappedRange) =
    set_line_slice(b, r.start, r.stop, true, true, lines)
Base.setindex!(b::Buffer, lines::Array, ::Colon) = b[1:end] = lines
Base.setindex!(b::Buffer, s::String, i::Integer) = b[i:i] = [s]
Base.setindex!(b::Buffer, s::String, i::EndRelIndex) = b[i:i] = [s]
Base.setindex!(b::Buffer, s::String, r::CappedRange) = b[r] = [s]
function Base.setindex!{T<:Integer}(b::Buffer, s::String, r::UnitRange{T})
    ndests = r.stop - r.start + 1
    ndests <= 0 ? s : b[r] = fill(s, ndests)
end
function Base.setindex!{T<:Integer}(b::Buffer, lines::Array, r::UnitRange{T})
    b[CappedRange(r.start, r.stop)] = lines
end

Base.push!(b::Buffer, items...) = (insert(b, -1, [items...]); b)
Base.append!(b::Buffer, items) = (insert(b, -1, items); b)
Base.unshift!(b::Buffer, items...) = (set_line_slice(b, 0, 0, true, false, [items...]); b)

Base.deleteat!(b::Buffer, i::Integer) = deleteat!(b, i:i)
Base.deleteat!{T<:Integer}(b::Buffer, rng::UnitRange{T}) = (b[rng] = []; b)
