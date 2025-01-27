module RedirectRequest

using URIs
using ..Messages
using ..Pairs: setkv
import ..Header
import ..@debug, ..DEBUG_LEVEL

export redirectlayer, nredirects

"""
    redirectlayer(req) -> HTTP.Response

Redirects the request in the case of 3xx response status.
"""
function redirectlayer(handler)
    return function(req; redirect::Bool=true, redirect_limit::Int=3, forwardheaders::Bool=true, response_stream=nothing, kw...)
        if !redirect || redirect_limit == 0
            # no redirecting
            return handler(req; redirect_limit=redirect_limit, kw...)
        end

        count = 0
        while true
            # Verify the url before making the request. Verification is done in
            # the redirect loop to also catch bad redirect URLs.
            verify_url(req.url)
            res = handler(req; redirect_limit=redirect_limit, kw...)

            if (count == redirect_limit ||  !isredirect(res)
                ||  (location = header(res, "Location")) == "")
                return res
            end

            # follow redirect
            oldurl = req.url
            url = resolvereference(req.url, location)
            req = Request(req.method, resource(url), copy(req.headers), req.body;
                url=url, version=req.version, responsebody=response_stream, parent=res, context=req.context)
            if forwardheaders
                req.headers = filter(req.headers) do (header, _)
                    # false return values are filtered out
                    if header == "Host"
                        return false
                    elseif (header in SENSITIVE_HEADERS && !isdomainorsubdomain(url.host, oldurl.host))
                        return false
                    else
                        return true
                    end
                end
            else
                req.headers = Header[]
            end
            @debug 1 "➡️  Redirect: $url"
            count += 1
        end
        @assert false "Unreachable!"
    end
end

function nredirects(req)
    return req.parent === nothing ? 0 : (1 + nredirects(req.parent.request))
end

const SENSITIVE_HEADERS = Set([
    "Authorization",
    "Www-Authenticate",
    "Cookie",
    "Cookie2"
])

function isdomainorsubdomain(sub, parent)
    sub == parent && return true
    endswith(sub, parent) || return false
    return sub[length(sub)-length(parent)] == '.'
end

function verify_url(url::URI)
    if !(url.scheme in ("http", "https", "ws", "wss"))
        throw(ArgumentError("missing or unsupported scheme in URL (expected http(s) or ws(s)): $(url)"))
    end
    if isempty(url.host)
        throw(ArgumentError("missing host in URL: $(url)"))
    end
end

end # module RedirectRequest
