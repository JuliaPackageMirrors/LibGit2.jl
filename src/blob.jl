export rawcontent, sloc, text, isbinary, lookup_blob, 
       blob_from_buffer, blob_from_workdir, blob_from_disk, blob_from_stream  

Base.sizeof(b::GitBlob) = begin
    @assert b.ptr != C_NULL
    return api.git_blob_rawsize(b.ptr)::Int64
end

#TODO: it would be better to implement julia's file api's

function rawcontent(b::GitBlob, max_bytes=-1)
    @assert b.ptr != C_NULL
    data_ptr = api.git_blob_rawcontent(b.ptr)
    data_size = api.git_blob_rawsize(b.ptr)
    if data_ptr == C_NULL || max_bytes == 0
        return Array(Uint8, 0)
    end
    if max_bytes < 0 || max_bytes > data_size
        data_copy = Array(Uint8, data_size)
        unsafe_copy!(pointer(data_copy), data_ptr, data_size)
        return data_copy
    end
    if max_bytes > 0 && max_bytes < data_size
        data_copy = Array(Uint8, max_bytes)
        unsafe_copy!(pointer(data_copy), data_ptr, max_bytes)
        return data_copy
    end
end

Base.bytestring(b::GitBlob) = bytestring(rawcontent(b))

function sloc(b::GitBlob)
    @assert b.ptr != nothing
    data_ptr = api.git_blob_rawcontent(b.ptr)
    data_end = data_ptr + api.git_blob_rawsize(b.ptr)
    if data_ptr == data_end
        return 0
    end
    loc = 0
    while uint(data_ptr) < uint(data_end)
        val = unsafe_load(data_ptr)
        data_ptr += 1
        if val == uint8(10) #"\n"
            while uint(data_ptr) < uint(data_end) && isspace(char(unsafe_load(data_ptr)))
                data_ptr += 1
            end
            loc += 1
        end
    end
    if unsafe_load(data_ptr-1) != uint8(10) #"\n"
        loc += 1
    end
    return loc
end

function text(b::GitBlob, max_lines=-1)
    @assert b.ptr != C_NULL
    data_ptr = api.git_blob_rawcontent(b.ptr)
    if data_ptr == C_NULL || max_lines == 0
        return bytestring("")
    elseif max_lines < 0
        return bytestring(data_ptr)
    end
    lines, i = 0, 1
    data_size = api.git_blob_rawsize(b.ptr)
    while i <= data_size && lines < max_lines
        if unsafe_load(data_ptr, i) == uint8(10) # "\n"
            lines += 1
        end
        i += 1
    end
    data_size = i - 1
    data_copy = Array(Uint8, data_size)
    unsafe_copy!(pointer(data_copy), data_ptr, data_size)
    return UTF8String(data_copy) 
end

function isbinary(b::GitBlob)
    @assert b.ptr != C_NULL
    res = api.git_blob_is_binary(b.ptr)
    return bool(res)
end

function blob_from_buffer(r::GitRepo, bufptr::Ptr{Uint8}, len::Int)
    id = Oid()
    @check ccall((:git_blob_create_frombuffer, api.libgit2), Cint,
                 (Ptr{Oid}, Ptr{Void}, Ptr{Uint8}, Csize_t),
                 &id, pointer(r), bufptr, len)
    return id
end

blob_from_buffer(r::GitRepo, buf::Vector{Uint8}) = blob_from_buffer(r::GitRepo, pointer(buf), length(buf))
blob_from_buffer(r::GitRepo, buf::ByteString)    = blob_from_buffer(r::GitRepo, buf.data)
blob_from_buffer(r::GitRepo, buf::IOBuffer)      = blob_from_buffer(r::GitRepo, buf.data)

function blob_from_workdir(r::GitRepo, path::String)
    id = Oid()
    @check ccall((:git_blob_create_fromworkdir, api.libgit2), Cint,
                  (Ptr{Oid}, Ptr{Void}, Ptr{Cchar}), 
                  &id, pointer(r), bytestring(path))
    return id
end

function blob_from_disk(r::GitRepo, path::String)
    id = Oid()
    @check ccall((:git_blob_create_fromdisk, api.libgit2), Cint,
                  (Ptr{Oid}, Ptr{Void}, Ptr{Cchar}), 
                  &id, pointer(r), bytestring(path))
    return id
end

function cb_blob_get_chunk(contentptr::Ptr{Uint8}, 
                           maxlen::Csize_t, 
                           payloadptr::Ptr{Void})
    payload = unsafe_pointer_to_objref(payloadptr)::Array{Any,1}
    io::IO = payload[1]
    local buff::Vector{Uint8}
    try
        buff = readbytes(io, maxlen)
    catch err
        payload[2] = err
        return api.ERROR
    end
    len = length(buff)
    len > maxlen && (len = maxlen)
    unsafe_copy!(contentptr, convert(Ptr{Uint8}, buff), len)
    return convert(Cint, len)
end

const c_cb_blob_get_chunk = cfunction(cb_blob_get_chunk, Cint,
                                      (Ptr{Uint8}, Csize_t, Ptr{Void}))

function blob_from_stream(r::GitRepo, io::IO, hintpath=nothing)
    id = Oid()
    if hintpath != nothing
        pathptr = convert(Ptr{Cchar}, pointer(bytestring(hintpath)))
    else
        pathptr = convert(Ptr{Cchar}, C_NULL)
    end
    payload = {io, nothing}
    err = ccall((:git_blob_create_fromchunks, api.libgit2), Cint,
                (Ptr{Oid}, Ptr{Void}, Ptr{Cchar}, Ptr{Void}, Any),
                &id, pointer(r), pathptr, c_cb_blob_get_chunk, &payload)
    if isa(payload[2], Exception)
        throw(payload[2])
    end
    if err != api.GIT_OK
        throw(LibGitError(err))
    end
    return id
end
