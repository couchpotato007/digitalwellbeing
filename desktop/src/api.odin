package main

// Talking to the wellbeing server. Every request is a `kiln.task`: libcurl runs on a worker
// thread and the answer comes back as a `Response` message. Requests carry a generation number,
// answers to outdated requests are dropped.

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:net"
import "core:strings"
import "lib:kiln"
import curl "vendor:curl"

Request_Kind :: enum {
	Stats, // GET /api/stats for the dashboard
	Block, // GET /api/block for a block of the activity view
	Test, // GET /api/stats for "Test connection"
}

// The answer to a request, a message of the app.
Response :: struct {
	kind:   Request_Kind,
	gen:    int,
	status: int, // HTTP status, 0 if the server could not be reached
	body:   string, // allocated, freed by `update`
	error:  string, // allocated, "" if the request went through
}

@(private = "file")
Request :: struct {
	kind:       Request_Kind,
	gen:        int,
	url, token: string,
}

api_init :: proc() {
	curl.global_init(3) // CURL_GLOBAL_ALL
}

// Starts a GET request of `path` (with query) on the server.
api_get :: proc(server: Server, kind: Request_Kind, gen: int, path: string) {
	kiln.task(
		run_request,
		Request {
			kind = kind,
			gen = gen,
			url = strings.concatenate({strings.trim_right(server.url, "/"), path}),
			token = strings.clone(server.token),
		},
	)
}

// Frees the strings of an answer.
response_destroy :: proc(r: Response) {
	delete(r.body)
	delete(r.error)
}

// `value` for a query string.
url_encode :: proc(value: string) -> string {
	return net.percent_encode(value, context.temp_allocator)
}

// What went wrong, in words for the UI. "" if the request worked.
describe :: proc(r: Response) -> string {
	switch {
	case len(r.error) > 0:
		return r.error
	case r.status == 401:
		return "The token is wrong"
	case r.status == 404:
		return "No wellbeing server at this URL"
	case r.status < 200 || r.status >= 300:
		return fmt.tprintf("The server answered %d %s", r.status, strings.trim_space(r.body))
	}
	return ""
}

@(private = "file")
run_request :: proc(req: Request) -> Response {
	defer {
		delete(req.url)
		delete(req.token)
	}
	r := Response {
		kind = req.kind,
		gen  = req.gen,
	}
	r.status, r.body, r.error = http_get(req.url, req.token)
	return r
}

@(private = "file")
http_get :: proc(url, token: string) -> (status: int, body: string, error: string) {
	h := curl.easy_init()
	if h == nil {return 0, "", strings.clone("Could not start libcurl")}
	defer curl.easy_cleanup(h)

	headers := curl.slist_append(nil, fmt.ctprintf("Authorization: Bearer %s", token))
	headers = curl.slist_append(headers, "Accept: application/json")
	defer curl.slist_free_all(headers)

	buf := make([dynamic]u8) // with the task's allocator, the callback runs in a default context
	errbuf: [256]u8 // CURL_ERROR_SIZE

	curl.easy_setopt(h, .URL, strings.clone_to_cstring(url, context.temp_allocator))
	curl.easy_setopt(h, .HTTPHEADER, headers)
	curl.easy_setopt(h, .WRITEFUNCTION, write_body)
	curl.easy_setopt(h, .WRITEDATA, &buf)
	curl.easy_setopt(h, .ERRORBUFFER, &errbuf[0])
	curl.easy_setopt(h, .FOLLOWLOCATION, c.long(1))
	curl.easy_setopt(h, .CONNECTTIMEOUT, c.long(10))
	curl.easy_setopt(h, .TIMEOUT, c.long(30))
	curl.easy_setopt(h, .NOSIGNAL, c.long(1))

	res := curl.easy_perform(h)
	if res != .E_OK {
		delete(buf)
		return 0, "", strings.clone(curl_error(res, string(cstring(&errbuf[0]))))
	}

	code: c.long
	curl.easy_getinfo(h, .RESPONSE_CODE, &code)
	return int(code), string(buf[:]), ""
}

@(private = "file")
write_body :: proc "c" (ptr: [^]byte, size, nitems: c.size_t, userdata: rawptr) -> c.size_t {
	context = runtime.default_context()
	buf := (^[dynamic]u8)(userdata)
	n := int(size * nitems)
	append(buf, ..ptr[:n])
	return c.size_t(n)
}

@(private = "file")
curl_error :: proc(res: curl.code, detail: string) -> string {
	#partial switch res {
	case .E_URL_MALFORMAT, .E_UNSUPPORTED_PROTOCOL:
		return "The URL is not valid"
	case .E_COULDNT_RESOLVE_HOST:
		return "Server not found, check the URL"
	case .E_COULDNT_CONNECT:
		return "Connection refused, is the server running?"
	case .E_OPERATION_TIMEDOUT:
		return "The server did not answer in time"
	}
	if len(detail) > 0 {return detail}
	return fmt.tprintf("Request failed (curl error %d)", int(res))
}
