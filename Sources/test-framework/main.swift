import Foundation
import HummingBirdFiles
import HummingBirdJSON
import HummingBird
import NIO
import NIOHTTP1

struct TestMiddleware: Middleware {
    func apply(to request: Request, next: RequestResponder) -> EventLoopFuture<Response> {
        return next.respond(to: request).map { response in
            if case .byteBuffer(var buffer) = response.body {
                buffer.writeString("\ntest\n")
                return Response(status: .ok, headers: response.headers, body: .byteBuffer(buffer))
            }
            return response
        }
    }
}

struct DebugMiddleware: Middleware {
    func apply(to request: Request, next: RequestResponder) -> EventLoopFuture<Response> {
        request.logger.debug("\(request.method): \(request.uri)")
        return next.respond(to: request)
    }
}

struct User: ResponseCodable {
    internal init(name: String, address: String? = nil, age: Int) {
        self.name = name
        self.address = address
        self.age = age
    }

    let name: String
    let address: String?
    let age: Int
}
let app = Application()
let env = Environment()
let host = env["HOST"] ?? "127.0.0.1"

app.addHTTPServer(.init(host: host, port:8080))
app.encoder = JSONEncoder()
app.decoder = JSONDecoder()

app.logger.logLevel = .info

app.middlewares.add(DebugMiddleware())
app.middlewares.add(FileMiddleware(app: app))

app.router.get("/") { request -> String in
    "This is a test"
}

app.router.get("/hello") { request -> EventLoopFuture<ByteBuffer> in
    let response = request.allocator.buffer(string: "Hello")
    return request.eventLoop.makeSucceededFuture(response)
}

app.router.get("/hello2") { request -> String in
    guard let name = request.uri.queryParameters["name"]?.removingPercentEncoding else { throw HTTPError(.badRequest, message: "You need a \"name\" query parameter.") }
    return "Hello \(name)"
}

app.router.get("/user") { request -> EventLoopFuture<User> in
    let name = request.uri.queryParameters["name"]?.removingPercentEncoding ?? "Unknown"
    return request.eventLoop.makeSucceededFuture(.init(name: String(name), age: 42))
}

app.router.put("/user/name") { request -> EventLoopFuture<String> in
    guard let user = try? request.decode(as: User.self) else { return request.eventLoop.makeFailedFuture(HTTPError(.badRequest)) }
    return request.eventLoop.makeSucceededFuture("Hello \(user.name)")
}

app.router.get("/user/{id}") { request -> String in
    return "User id: \(request.parameters.get("id", as: Int.self) ?? 0)"
}

app.router.put("/user") { request -> User in
    guard let user = try? request.decode(as: User.self) else { throw HTTPError(.badRequest) }
    let newUser = User(name: user.name, age: user.age+1)
    return newUser
}

app.router.put("/user-future") { request -> EventLoopFuture<User> in
    guard let user = try? request.decode(as: User.self) else { return request.eventLoop.makeFailedFuture(HTTPError(.badRequest)) }
    let newUser = User(name: user.name, age: user.age+1)
    return request.eventLoop.makeSucceededFuture(newUser)
}
app.router.get("/string") { request -> String in
    return "Hello"
}

let group = app.router.group()
    .add(middleware: TestMiddleware())

group.get("/test") { request -> EventLoopFuture<ByteBuffer> in
    let response = request.allocator.buffer(string: "GoodBye")
    return request.eventLoop.makeSucceededFuture(response)
}

app.start()
app.wait()
