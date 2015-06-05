# high-level interface and shorthands

export current_window, current_buffer, current_tabpage, current_line, set_current, set_current_line, cursor
current_window(c::NvimClient) = get_current_window(c)
current_buffer(c::NvimClient) = get_current_buffer(c)
current_tabpage(c::NvimClient) = get_current_tabpage(c)
current_line(c::NvimClient) = get_current_line(c)

set_current(o::Buffer) = set_current_buffer(o.client, o)
set_current(o::Window) = set_current_window(o.client, o)
set_current(o::Tabpage) = set_current_tabpage(o.client, o)

cursor(c::Window) = get_cursor(c) + [0, 1]
cursor(o::Window, p::Array{Int,1}) = set_cursor(o, p - [0, 1])

# array interface for buffer
Base.length(b::Buffer) = line_count(b)
Base.getindex(b::Buffer, idx::Integer) = get_line(b, idx-1)
Base.setindex!(b::Buffer, str, idx::Integer) = set_line(b, idx-1, str)

# we could use endof(b)=line_count(b) but that is non-atomic,
# i.e. buffer length could change between line_count and set_slice
# XXX: this is very ad-hoc, but I don't know a better way...
immutable VimIndex
    i::Int
end
Base.endof(b::Buffer) = VimIndex(-1)
-(a::VimIndex, b::Integer) = VimIndex(a.i-b)
+(a::VimIndex, b::Integer) = VimIndex(a.i+b)
immutable VimRange
    start::Int
    stop::Int
end
Base.colon(a::Integer, b::VimIndex) = VimRange(a-1,b.i)
Base.colon(a::VimIndex, b::Integer) = VimRange(a.i,b-1)
Base.colon(a::VimIndex, b::VimIndex) = VimRange(a.i,b.i)
Base.getindex(b::Buffer, r::VimRange) = get_line_slice(b, r.start, r.stop, true, true)
Base.getindex{T<:Integer}(b::Buffer, r::UnitRange{T}) = get_line_slice(b, r.start-1, r.stop-1, true, true)
Base.setindex!(b::Buffer, lines,  r::VimRange) = set_line_slice(b, r.start, r.stop, true, true, lines)
Base.setindex!{T<:Integer}(b::Buffer, lines, r::UnitRange{T}) = set_line_slice(b, r.start-1, r.stop-1, true, true, lines)

Base.push!(b::Buffer, items...) = (insert(b, -1, [items...]); b)
Base.append!(b::Buffer, items) = (insert(b, -1, items); b)
Base.unshift!(b::Buffer, items...) = (set_line_slice(b, 0, 0, true, false, [items...]); b)

Base.deleteat!(b::Buffer, i::Integer) = deleteat!(b, i:i)
Base.deleteat!{T<:Integer}(b::Buffer, rng::UnitRange{T}) = (b[rng] = []; b)
