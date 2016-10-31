describe("http.request module", function()
	local request = require "http.request"
	local http_util = require "http.util"
	it("can construct a request from a uri", function()
		do -- http url; no path
			local req = request.new_from_uri("http://example.com")
			assert.same("example.com", req.host)
			assert.same(80, req.port)
			assert.falsy(req.tls)
			assert.same("example.com", req.headers:get ":authority")
			assert.same("GET", req.headers:get ":method")
			assert.same("/", req.headers:get ":path")
			assert.same("http", req.headers:get ":scheme")
			assert.same(nil, req.body)
		end
		do -- https
			local req = request.new_from_uri("https://example.com/path?query")
			assert.same("example.com", req.host)
			assert.same(443, req.port)
			assert.truthy(req.tls)
			assert.same("example.com", req.headers:get ":authority")
			assert.same("GET", req.headers:get ":method")
			assert.same("/path?query", req.headers:get ":path")
			assert.same("https", req.headers:get ":scheme")
			assert.same(nil, req.body)
		end
		do -- needs url normalisation
			local req = request.new_from_uri("HTTP://exaMple.com/1%323%2f45?foo=ba%26r&another=more")
			assert.same("example.com", req.host)
			assert.same(80, req.port)
			assert.falsy(req.tls)
			assert.same("example.com", req.headers:get ":authority")
			assert.same("GET", req.headers:get ":method")
			assert.same("/123%2F45?foo=ba%26r&another=more", req.headers:get ":path")
			assert.same("http", req.headers:get ":scheme")
			assert.same(nil, req.body)
		end
		do -- with userinfo section
			local basexx = require "basexx"
			local req = request.new_from_uri("https://user:password@example.com/")
			assert.same("example.com", req.host)
			assert.same(443, req.port)
			assert.truthy(req.tls)
			assert.same("example.com", req.headers:get ":authority")
			assert.same("GET", req.headers:get ":method")
			assert.same("/", req.headers:get ":path")
			assert.same("https", req.headers:get ":scheme")
			assert.same("user:password", basexx.from_base64(req.headers:get "authorization":match "^basic%s+(.*)"))
			assert.same(nil, req.body)
		end
	end)
	it("can construct a request with custom proxies object", function()
		local http_proxies = require "http.proxies"
		-- No proxies
		local proxies = http_proxies.new():update(function() end)
		local req = request.new_from_uri("http://example.com", nil, proxies)
		assert.same("example.com", req.host)
		assert.same(80, req.port)
		assert.falsy(req.tls)
		assert.same("example.com", req.headers:get ":authority")
		assert.same("GET", req.headers:get ":method")
		assert.same("/", req.headers:get ":path")
		assert.same("http", req.headers:get ":scheme")
		assert.same(nil, req.body)
	end)
	it("can construct a CONNECT request", function()
		do -- http url; no path
			local req = request.new_connect("http://example.com", "connect.me")
			assert.same("example.com", req.host)
			assert.same(80, req.port)
			assert.falsy(req.tls)
			assert.same("connect.me", req.headers:get ":authority")
			assert.same("CONNECT", req.headers:get ":method")
			assert.falsy(req.headers:has ":path")
			assert.falsy(req.headers:has ":scheme")
			assert.same(nil, req.body)
		end
		do -- https
			local req = request.new_connect("https://example.com", "connect.me:1234")
			assert.same("example.com", req.host)
			assert.same(443, req.port)
			assert.truthy(req.tls)
			assert.same("connect.me:1234", req.headers:get ":authority")
			assert.same("CONNECT", req.headers:get ":method")
			assert.falsy(req.headers:has ":path")
			assert.falsy(req.headers:has ":scheme")
			assert.same(nil, req.body)
		end
		do -- with userinfo section
			local basexx = require "basexx"
			local req = request.new_connect("https://user:password@example.com", "connect.me")
			assert.same("example.com", req.host)
			assert.same(443, req.port)
			assert.truthy(req.tls)
			assert.same("connect.me", req.headers:get ":authority")
			assert.same("CONNECT", req.headers:get ":method")
			assert.falsy(req.headers:has ":path")
			assert.falsy(req.headers:has ":scheme")
			assert.same("user:password", basexx.from_base64(req.headers:get "proxy-authorization":match "^basic%s+(.*)"))
			assert.same(nil, req.body)
		end
		do -- anything with a path should fail
			assert.has.errors(function() request.new_connect("http://example.com/") end)
			assert.has.errors(function() request.new_connect("http://example.com/path") end)
		end
	end)
	it("fails on invalid URIs", function()
		assert.has.errors(function() request.new_from_uri("not a URI") end)

		-- no scheme
		assert.has.errors(function() request.new_from_uri("example.com") end)

		-- trailing junk
		assert.has.errors(function() request.new_from_uri("example.com/foo junk.") end)
	end)
	it("can (sometimes) roundtrip via :to_uri()", function()
		local function test(uri)
			local req = request.new_from_uri(uri)
			assert.same(uri, req:to_uri(true))
		end
		test("http://example.com/")
		test("https://example.com/")
		test("https://example.com:1234/")
		test("http://foo:bar@example.com:1234/path?query")
		test("https://fo%20o:ba%20r@example.com:1234/path%20spaces")
	end)
	it(":to_uri() throws on un-coerable authorization", function()
		assert.has.errors(function()
			local req = request.new_from_uri("http://example.com/")
			req.headers:upsert("authorization", "singletoken")
			req:to_uri(true)
		end)
		assert.has.errors(function()
			local req = request.new_from_uri("http://example.com/")
			req.headers:upsert("authorization", "can't go in a uri")
			req:to_uri(true)
		end)
		assert.has.errors(function()
			local req = request.new_from_uri("http://example.com/")
			req.headers:upsert("authorization", "basic trailing data")
			req:to_uri(true)
		end)
		assert.has.errors(function()
			local req = request.new_from_uri("http://example.com/")
			req.headers:upsert("authorization", "bearer data")
			req:to_uri(true)
		end)
	end)
	it("handles CONNECT requests in :to_uri()", function()
		local function test(uri)
			local req = request.new_connect(uri, "connect.me")
			assert.same(uri, req:to_uri(true))
		end
		test("http://example.com")
		test("https://example.com")
		test("https://example.com:1234")
		test("https://foo:bar@example.com:1234")
		assert.has.errors(function() test("https://example.com/path") end)
	end)
	describe(":to_curl() #curl", function()
		it("lua-http defaults", function()
			local req = request.new_from_uri("http://example.com/")
			req.headers:delete "user-agent" -- take variability out of tests
			assert.same("curl --location-trusted -e ';auto' --max-redirs 5 http://example.com/", req:to_curl())
		end)
		local req_template = request.new_from_uri("http://example.com/")
		req_template.headers:delete "user-agent" -- take variability out of tests
		req_template.follow_redirects = false -- closer to curl defaults
		req_template.max_redirects = 50
		it("curl defaults", function()
			local req = req_template:clone()
			assert.same("curl http://example.com/", req:to_curl())
		end)
		it("http version 1.0", function()
			local req = req_template:clone()
			req.version = 1
			assert.same("curl -0 http://example.com/", req:to_curl())
		end)
		it("http version 1.1", function()
			local req = req_template:clone()
			req.version = 1.1
			assert.same("curl --http1.1 http://example.com/", req:to_curl())
		end)
		it("http version 2", function()
			local req = req_template:clone()
			req.version = 2
			assert.same("curl --http2 http://example.com/", req:to_curl())
		end)
		it("expect_100_timeout flag", function()
			local req = req_template:clone()
			req.expect_100_timeout = 2
			assert.same("curl --expect100-timeout 2 http://example.com/", req:to_curl())
		end)
		it("post301 flag", function()
			local req = req_template:clone()
			req.follow_redirects = nil
			req.post301 = true
			assert.same("curl --location-trusted -e ';auto' --post301 http://example.com/", req:to_curl())
		end)
		it("post302 flag", function()
			local req = req_template:clone()
			req.follow_redirects = nil
			req.post302 = true
			assert.same("curl --location-trusted -e ';auto' --post302 http://example.com/", req:to_curl())
		end)
		it("path component", function()
			local req = req_template:clone()
			req.headers:upsert(":path", "/[complex]&path{component}")
			assert.same("curl -g 'http://example.com/[complex]&path{component}'", req:to_curl())
		end)
		it("query component", function()
			local req = req_template:clone()
			req.headers:upsert(":path", "/path?query")
			assert.same("curl 'http://example.com/path?query'", req:to_curl())
		end)
		it("scheme change", function()
			local req = req_template:clone()
			req.headers:upsert(":scheme", "https")
			assert.same("curl https://example.com:80/ -H 'host: example.com'", req:to_curl())
		end)
		it("scheme and port change", function()
			local req = req_template:clone()
			req.headers:upsert(":scheme", "https")
			req.port = 443
			assert.same("curl https://example.com/", req:to_curl())
		end)
		it("port change", function()
			local req = req_template:clone()
			req.port = 443
			assert.same("curl http://example.com:443/ -H 'host: example.com'", req:to_curl())
		end)
		it("host change", function()
			local req = req_template:clone()
			req.headers:upsert(":authority", "foo.com")
			assert.same("curl http://example.com/ -H 'host: foo.com'", req:to_curl())
		end)
		it("head method", function()
			local req = req_template:clone()
			req.headers:upsert(":method", "HEAD")
			assert.same("curl http://example.com/ -I", req:to_curl())
		end)
		it("post method with body", function()
			local req = req_template:clone()
			req.headers:upsert(":method", "POST")
			req.body = "foo"
			assert.same("curl http://example.com/ --data-raw foo", req:to_curl())
		end)
		it("post method without body", function()
			local req = req_template:clone()
			req.headers:upsert(":method", "POST")
			assert.same("curl http://example.com/ -X POST", req:to_curl())
		end)
		it("custom headers", function()
			local req = req_template:clone()
			req.headers:append("foo", "bar")
			assert.same("curl http://example.com/ -H 'foo: bar'", req:to_curl())
		end)
	end)
	it(":set_body sets content-length for string arguments", function()
		local req = request.new_from_uri("http://example.com")
		assert.falsy(req.headers:has("content-length"))
		local str = "a string"
		req:set_body(str)
		assert.same(string.format("%d", #str), req.headers:get("content-length"))
	end)
	it(":set_body sets expect 100-continue for file arguments", function()
		local req = request.new_from_uri("http://example.com")
		assert.falsy(req.headers:has("expect"))
		req:set_body(io.tmpfile())
		assert.same("100-continue", req.headers:get("expect"))
	end)
	describe(":handle_redirect method", function()
		local headers = require "http.headers"
		it("works", function()
			local orig_req = request.new_from_uri("http://example.com")
			local orig_headers = headers.new()
			orig_headers:append(":status", "301")
			orig_headers:append("location", "/foo")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.host, new_req.host)
			assert.same(orig_req.port, new_req.port)
			assert.same(orig_req.tls, new_req.tls)
			assert.same(orig_req.headers:get ":authority", new_req.headers:get ":authority")
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same("/foo", new_req.headers:get ":path")
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("works with cross-scheme port-less uri", function()
			local orig_req = request.new_from_uri("http://example.com")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "https://blah.com/example")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same(false, orig_req.tls)
			assert.same(true, new_req.tls)
			assert.same("https", new_req.headers:get ":scheme")
			assert.same("blah.com", new_req.host)
			assert.same(80, orig_req.port)
			assert.same(443, new_req.port)
			assert.same("blah.com", new_req.headers:get ":authority")
			assert.same("/example", new_req.headers:get ":path")
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("works with scheme relative uri with just domain", function()
			local orig_req = request.new_from_uri("http://example.com")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "//blah.com")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.port, new_req.port)
			assert.same(orig_req.tls, new_req.tls)
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same("blah.com", new_req.host)
			assert.same("blah.com", new_req.headers:get ":authority")
			assert.same("/", new_req.headers:get ":path")
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("works with scheme relative uri", function()
			local orig_req = request.new_from_uri("http://example.com")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "//blah.com:1234/example")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.tls, new_req.tls)
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same("blah.com", new_req.host)
			assert.same(1234, new_req.port)
			assert.same("blah.com:1234", new_req.headers:get ":authority")
			assert.same("/example", new_req.headers:get ":path")
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("adds authorization headers for redirects with userinfo", function()
			local basexx = require "basexx"
			local orig_req = request.new_from_uri("http://example.com")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "http://user:passwd@blah.com/")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.port, new_req.port)
			assert.same(orig_req.tls, new_req.tls)
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same("blah.com", new_req.host)
			assert.same("blah.com", new_req.headers:get ":authority")
			assert.same("/", new_req.headers:get ":path")
			assert.same("basic " .. basexx.to_base64("user:passwd"), new_req.headers:get("authorization"))
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("simplifies relative paths", function()
			local orig_req = request.new_from_uri("http://example.com/foo/test")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "../bar")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.host, new_req.host)
			assert.same(orig_req.port, new_req.port)
			assert.same(orig_req.tls, new_req.tls)
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same("example.com", new_req.headers:get ":authority")
			assert.same("/bar", new_req.headers:get ":path")
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("rejects relative redirects when base is invalid", function()
			local ce = require "cqueues.errno"
			local orig_req = request.new_from_uri("http://example.com")
			orig_req.headers:upsert(":path", "^")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "../path")
			assert.same({nil, "base path not valid for relative redirect", ce.EINVAL}, {orig_req:handle_redirect(orig_headers)})
		end)
		it("works with query in uri", function()
			local orig_req = request.new_from_uri("http://example.com/path?query")
			local orig_headers = headers.new()
			orig_headers:append(":status", "301")
			orig_headers:append("location", "/foo?anotherquery")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.host, new_req.host)
			assert.same(orig_req.port, new_req.port)
			assert.same(orig_req.tls, new_req.tls)
			assert.same(orig_req.headers:get ":authority", new_req.headers:get ":authority")
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same("/foo?anotherquery", new_req.headers:get ":path")
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("detects maximum redirects exceeded", function()
			local ce = require "cqueues.errno"
			local orig_req = request.new_from_uri("http://example.com")
			orig_req.max_redirects = 0
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "/")
			assert.same({nil, "maximum redirects exceeded", ce.ELOOP}, {orig_req:handle_redirect(orig_headers)})
		end)
		it("detects missing location header", function()
			local ce = require "cqueues.errno"
			local orig_req = request.new_from_uri("http://example.com")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			assert.same({nil, "missing location header for redirect", ce.EINVAL}, {orig_req:handle_redirect(orig_headers)})
		end)
		it("detects invalid location header", function()
			local ce = require "cqueues.errno"
			local orig_req = request.new_from_uri("http://example.com")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "this isn't valid")
			assert.same({nil, "invalid URI in location header", ce.EINVAL}, {orig_req:handle_redirect(orig_headers)})
		end)
		it("detects POST => GET transformation", function()
			local orig_req = request.new_from_uri("http://example.com")
			orig_req.headers:upsert(":method", "POST")
			orig_req.headers:upsert("content-type", "text/plain")
			orig_req:set_body(("foo"):rep(1000)) -- make sure it's big enough to automatically add an "expect" header
			local orig_headers = headers.new()
			orig_headers:append(":status", "303")
			orig_headers:append("location", "/foo")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.host, new_req.host)
			assert.same(orig_req.port, new_req.port)
			assert.same(orig_req.tls, new_req.tls)
			assert.same(orig_req.headers:get ":authority", new_req.headers:get ":authority")
			assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
			-- different
			assert.same("GET", new_req.headers:get ":method")
			assert.same("/foo", new_req.headers:get ":path")
			assert.falsy(new_req.headers:get "expect")
			assert.falsy(new_req.headers:has "content-type")
			assert.same(nil, new_req.body)
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("deletes keeps original custom host, port and sendname if relative", function()
			local orig_req = request.new_from_uri("http://example.com")
			orig_req.host = "other.com"
			orig_req.sendname = "something.else"
			local orig_headers = headers.new()
			orig_headers:append(":status", "301")
			orig_headers:append("location", "/foo")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.host, new_req.host)
			assert.same(orig_req.port, new_req.port)
			assert.same(orig_req.tls, new_req.tls)
			assert.same(orig_req.sendname, new_req.sendname)
			assert.same(orig_req.headers:get ":authority", new_req.headers:get ":authority")
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same("/foo", new_req.headers:get ":path")
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("removes referer header on https => http redirect", function()
			local orig_req = request.new_from_uri("https://example.com")
			local orig_headers = headers.new()
			orig_headers:append(":status", "301")
			orig_headers:append("location", "http://blah.com/foo")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same("blah.com", new_req.host)
			assert.same(80, new_req.port)
			assert.same(false, new_req.tls)
			assert.same("http", new_req.headers:get ":scheme")
			assert.same("blah.com", new_req.headers:get ":authority")
			assert.same("/foo", new_req.headers:get ":path")
			assert.falsy(new_req.headers:has "referer")
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("doesn't attach userinfo to referer header", function()
			local orig_req = request.new_from_uri("http://user:passwd@example.com")
			local orig_headers = headers.new()
			orig_headers:append(":status", "301")
			orig_headers:append("location", "/foo")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.host, new_req.host)
			assert.same(orig_req.port, new_req.port)
			assert.same(orig_req.tls, new_req.tls)
			assert.same(orig_req.headers:get ":authority", new_req.headers:get ":authority")
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.same(orig_req.headers:get ":scheme", new_req.headers:get ":scheme")
			assert.same(orig_req.body, new_req.body)
			-- different
			assert.same("/foo", new_req.headers:get ":path")
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
			assert.same("http://example.com/", new_req.headers:get "referer")
		end)
		it("works with CONNECT requests", function()
			local orig_req = request.new_connect("http://example.com", "connect.me")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "http://other.com")
			local new_req = orig_req:handle_redirect(orig_headers)
			-- same
			assert.same(orig_req.port, new_req.port)
			assert.same(orig_req.tls, new_req.tls)
			assert.falsy(new_req.headers:has ":path")
			assert.same(orig_req.headers:get ":authority", new_req.headers:get ":authority")
			assert.same(orig_req.headers:get ":method", new_req.headers:get ":method")
			assert.falsy(new_req.headers:has ":scheme")
			assert.same(nil, new_req.body)
			-- different
			assert.same("other.com", new_req.host)
			assert.same(orig_req.max_redirects-1, new_req.max_redirects)
		end)
		it("rejects invalid CONNECT redirects", function()
			local ce = require "cqueues.errno"
			local orig_req = request.new_connect("http://example.com", "connect.me")
			local orig_headers = headers.new()
			orig_headers:append(":status", "302")
			orig_headers:append("location", "/path")
			assert.same({nil, "CONNECT requests cannot have a path", ce.EINVAL}, {orig_req:handle_redirect(orig_headers)})
			orig_headers:upsert("location", "?query")
			assert.same({nil, "CONNECT requests cannot have a query", ce.EINVAL}, {orig_req:handle_redirect(orig_headers)})
		end)
	end)
	describe(":go method", function()
		local cqueues = require "cqueues"
		local server = require "http.server"
		local new_headers = require "http.headers".new
		local function test(server_cb, client_cb)
			local cq = cqueues.new()
			local s = server.listen {
				host = "localhost";
				port = 0;
				onstream = function(s, stream)
					local keep_going = server_cb(stream, s)
					stream:shutdown()
					stream.connection:shutdown()
					if not keep_going then
						s:close()
					end
				end;
			}
			assert(s:listen())
			local _, host, port = s:localname()
			cq:wrap(function()
				assert_loop(s)
			end)
			cq:wrap(function()
				local req = request.new_from_uri {
					scheme = "http";
					host = host;
					port = port;
				}
				client_cb(req)
			end)
			assert_loop(cq, TEST_TIMEOUT)
			assert.truthy(cq:empty())
		end
		it("works with local server", function()
			test(function(stream)
				assert(stream:get_headers())
				local resp_headers = new_headers()
				resp_headers:append(":status", "200")
				assert(stream:write_headers(resp_headers, false))
				assert(stream:write_chunk("hello world", true))
			end, function(req)
				local headers, stream = assert(req:go())
				assert.same("200", headers:get(":status"))
				assert.same("hello world", assert(stream:get_body_as_string()))
				stream:shutdown()
			end)
		end)
		it("waits for 100-continue before sending body", function()
			local has_sent_continue = false
			test(function(stream)
				assert(stream:get_headers())
				cqueues.sleep(0.1)
				assert(stream:write_continue())
				has_sent_continue = true
				assert.same("foo", assert(stream:get_body_as_string()))
				local resp_headers = new_headers()
				resp_headers:append(":status", "204")
				assert(stream:write_headers(resp_headers, true))
			end, function(req)
				req:set_body(coroutine.wrap(function()
					assert.truthy(has_sent_continue)
					coroutine.yield("foo")
				end))
				local headers, stream = assert(req:go())
				assert.same("204", headers:get(":status"))
				stream:shutdown()
			end)
		end)
		it("continues (eventually) if there is no 100-continue", function()
			test(function(stream)
				assert(stream:get_headers())
				assert.same("foo", assert(stream:get_body_as_string()))
				local resp_headers = new_headers()
				resp_headers:append(":status", "204")
				assert(stream:write_headers(resp_headers, true))
			end, function(req)
				req.expect_100_timeout = 0.2
				req:set_body(coroutine.wrap(function()
					coroutine.yield("foo")
				end))
				local headers, stream = assert(req:go())
				assert.same("204", headers:get(":status"))
				stream:shutdown()
			end)
		end)
		it("skips sending body if expect set and no 100 received", function()
			test(function(stream)
				assert(stream:get_headers())
				local resp_headers = new_headers()
				resp_headers:append(":status", "500")
				assert(stream:write_headers(resp_headers, true))
			end, function(req)
				local body = spy.new(function() end)
				req:set_body(body)
				local headers, stream = assert(req:go())
				assert.same("500", headers:get(":status"))
				assert.spy(body).was_not.called()
				stream:shutdown()
			end)
		end)
		it("works with file body", function()
			local file = io.tmpfile()
			assert(file:write("hello world"))
			test(function(stream)
				assert(stream:get_headers())
				assert(stream:write_continue())
				assert.same("hello world", assert(stream:get_body_as_string()))
				local resp_headers = new_headers()
				resp_headers:append(":status", "200")
				assert(stream:write_headers(resp_headers, false))
				assert(stream:write_chunk("goodbye world", true))
			end, function(req)
				req:set_body(file)
				local headers, stream = assert(req:go())
				assert.same("200", headers:get(":status"))
				assert.same("goodbye world", assert(stream:get_body_as_string()))
				stream:shutdown()
			end)
		end)
		it("follows redirects", function()
			local n = 0
			test(function(stream)
				n = n + 1
				if n == 1 then
					local h = assert(stream:get_headers())
					assert.same("/", h:get(":path"))
					local resp_headers = new_headers()
					resp_headers:append(":status", "302")
					resp_headers:append("location", "/foo")
					assert(stream:write_headers(resp_headers, true))
					return true
				elseif n == 2 then
					local h = assert(stream:get_headers())
					assert.same("/foo", h:get(":path"))
					local resp_headers = new_headers()
					resp_headers:append(":status", "200")
					assert(stream:write_headers(resp_headers, false))
					assert(stream:write_chunk("hello world", true))
				end
			end, function(req)
				local headers, stream = assert(req:go())
				assert.same("200", headers:get(":status"))
				assert.same("hello world", assert(stream:get_body_as_string()))
				stream:shutdown()
			end)
		end)
		it("works with a proxy server", function()
			test(function(stream)
				local h = assert(stream:get_headers())
				local _, host, port = stream:localname()
				local authority = http_util.to_authority(host, port, "http")
				assert.same(authority, h:get ":authority")
				assert.same("http://" .. authority .. "/", h:get(":path"))
				local resp_headers = new_headers()
				resp_headers:append(":status", "200")
				assert(stream:write_headers(resp_headers, false))
				assert(stream:write_chunk("hello world", true))
			end, function(req)
				req.proxy = {
					scheme = "http";
					host = req.host;
					port = req.port;
				}
				local headers, stream = assert(req:go())
				assert.same("200", headers:get(":status"))
				assert.same("hello world", assert(stream:get_body_as_string()))
				stream:shutdown()
			end)
		end)
		it("works with http proxies on OPTIONS requests", function()
			test(function(stream)
				local h = assert(stream:get_headers())
				assert.same("OPTIONS", h:get ":method")
				local _, host, port = stream:localname()
				assert.same("http://" .. http_util.to_authority(host, port, "http"), h:get(":path"))
				stream:shutdown()
			end, function(req)
				req.headers:upsert(":method", "OPTIONS")
				req.headers:upsert(":path", "*")
				req.proxy = {
					scheme = "http";
					host = req.host;
					port = req.port;
				}
				local _, stream = assert(req:go())
				stream:shutdown()
			end)
		end)
		it("adds proxy-authorization header", function()
			local basexx = require "basexx"
			test(function(stream)
				local h = assert(stream:get_headers())
				assert.same("basic " ..basexx.to_base64("user:pass"), h:get "proxy-authorization")
				stream:shutdown()
			end, function(req)
				req.proxy = {
					scheme = "http";
					host = req.host;
					port = req.port;
					userinfo = "user:pass";
				}
				local _, stream = assert(req:go())
				stream:shutdown()
			end)
		end)
		it(":handle_redirect doesn't drop proxy use within a domain", function()
			test(function(stream)
				local h = assert(stream:get_headers())
				local _, host, port = stream:localname()
				local authority = http_util.to_authority(host, port, "http")
				assert.same(authority, h:get ":authority")
				assert.same("http://" .. authority .. "/foo", h:get(":path"))
				stream:shutdown()
			end, function(req)
				req.proxy = {
					scheme = "http";
					host = req.host;
					port = req.port;
					userinfo = "user:pass";
				}
				local orig_headers = new_headers()
				orig_headers:append(":status", "302")
				orig_headers:append("location", "/foo")
				local new_req = req:handle_redirect(orig_headers)
				local _, stream = assert(new_req:go())
				stream:shutdown()
			end)
		end)
		it("CONNECT proxy", function()
			test(function(stream, s)
				local h = assert(stream:get_headers())
				local resp_headers = new_headers()
				resp_headers:append(":status", "200")
				assert(stream:write_headers(resp_headers, false))
				if h:get(":method") == "CONNECT" then
					assert(stream.connection.version < 2)
					local sock = assert(stream.connection:take_socket())
					s:add_socket(sock)
					return true
				else
					assert(stream:write_chunk("hello world", true))
				end
			end, function(req)
				req.tls = true
				req.proxy = {
					scheme = "http";
					host = req.host;
					port = req.port;
					userinfo = "user:pass";
				}
				local headers, stream = assert(req:go())
				assert.same("200", headers:get(":status"))
				assert.same("hello world", assert(stream:get_body_as_string()))
				stream:shutdown()
			end)
		end)
		it("fails correctly on non CONNECT proxy", function()
			test(function(stream)
				local h = assert(stream:get_headers())
				assert.same("CONNECT", h:get(":method"))
				local sock = stream.connection:take_socket()
				assert(sock:write("foo"))
				sock:close()
			end, function(req)
				req.tls = true
				req.proxy = {
					scheme = "http";
					host = req.host;
					port = req.port;
					userinfo = "user:pass";
				}
				local ok = req:go()
				assert.falsy(ok)
			end)
		end)
		it("fails correctly on failed CONNECT proxy attempt", function()
			test(function(stream)
				local h = assert(stream:get_headers())
				assert.same("CONNECT", h:get(":method"))
				local resp_headers = new_headers()
				resp_headers:append(":status", "400")
				assert(stream:write_headers(resp_headers, true))
			end, function(req)
				req.tls = true
				req.proxy = {
					scheme = "http";
					host = req.host;
					port = req.port;
					userinfo = "user:pass";
				}
				local ok = req:go()
				assert.falsy(ok)
			end)
		end)
		it("can make request via SOCKS proxy", function()
			local cs = require "cqueues.socket"
			local socks_server = cs.listen {
				family = cs.AF_INET;
				host = "localhost";
				port = 0;
			}
			assert(socks_server:listen())
			local _, socks_host, socks_port = socks_server:localname()

			local s = server.listen {
				host = "localhost";
				port = 0;
				onstream = function(s, stream)
					assert(stream:get_headers())
					local resp_headers = new_headers()
					resp_headers:append(":status", "200")
					assert(stream:write_headers(resp_headers, false))
					assert(stream:write_chunk("hello world", true))
					stream:shutdown()
					stream.connection:shutdown()
					s:close()
				end;
			}
			assert(s:listen())
			local _, host, port = s:localname()

			local cq = cqueues.new()
			cq:wrap(function()
				assert_loop(s)
			end)
			cq:wrap(function()
				local req = request.new_from_uri {
					scheme = "http";
					host = host;
					port = port;
				}
				req.proxy = {
					scheme = "socks5h";
					host = socks_host;
					port = socks_port;
				}
				local headers, stream = assert(req:go())
				assert.same("200", headers:get(":status"))
				assert.same("hello world", assert(stream:get_body_as_string()))
				stream:shutdown()
			end)
			cq:wrap(function() -- SOCKS server
				local sock = socks_server:accept()
				assert.same("\5", sock:read(1))
				local n = assert(sock:read(1)):byte()
				local available_auth = assert(sock:read(n))
				assert.same("\0", available_auth)
				assert(sock:xwrite("\5\0", "n"))
				assert.same("\5\1\0\1", sock:read(4))
				assert(sock:read(6)) -- ip + port
				assert(sock:xwrite("\5\0\0\3\4test\4\210", "n"))
				s:add_socket(sock)
			end)
			assert_loop(cq, TEST_TIMEOUT)
			assert.truthy(cq:empty())
			socks_server:close()
		end)
	end)
end)
