export Signature, name, email, time, time_offset

type Signature
    name::Ptr{Cchar}
    email::Ptr{Cchar}
    time::Int64
    time_offset::Cint
end

free!(s::Signature) = begin
    if s.name != C_NULL
        c_free(s.name)
    end
    s.name = C_NULL
    if s.email != C_NULL
        c_free(s.email)
    end
    s.email = C_NULL
end

# Get signature at time...
function Signature(name::String, email::String, time::Int64, offset::Int)
    bname  = bytestring(name)
    bemail = bytestring(email)
    sig_ptr = Array(Ptr{Signature}, 1)
    err_code  = ccall((:git_signature_new, :libgit2), Cint,
                      (Ptr{Ptr{Signature}}, Ptr{Cchar}, Ptr{Cchar}, Int64, Cint),
                      sig_ptr, bname, bemail, time, offset)
    if err_code < 0
        throw(GitError(err_code))
    end
    sig = unsafe_load(sig_ptr[1])
    finalizer(sig, free!)
    return sig
end

# Get signature now...
function Signature(name::String, email::String)
    bname = bytestring(name)
    bemail = bytestring(email)
    sig_ptr = Array(Ptr{Signature}, 1)
    err_code = ccall((:git_signature_now, :libgit2), Cint,
                     (Ptr{Ptr{Signature}}, Ptr{Cchar}, Ptr{Cchar}),
                     sig_ptr, bname, bemail)
    if err_code < 0
        throw(GitError(err_code))
    end
    sig = unsafe_load(sig_ptr[1])
    finalizer(sig, free!)
    return sig
end

function name(s::Signature)
    if s.name != C_NULL
        return bytestring(s.name)
    end
    return nothing
end

function email(s::Signature)
    if s.email != C_NULL
        return bytestring(s.email)
    end
    return nothing
end

function Base.time(s::Signature)
    return s.time
end

function time_offset(s::Signature)
    return s.time_offset
end