package finalwork

import std.collection.*
import std.fs.*
import std.net.*

const WEB_INDEX_PATH = "web/index.html"
const WEB_APP_PATH = "web/app.js"
const WEB_STYLE_PATH = "web/styles.css"
const HTTP_BUFFER_SIZE = 4096

struct ApiResult {
    let httpStatus: UInt16
    let code: Int64
    let message: String
    let dataJson: String

    public init(httpStatus: UInt16, code: Int64, message: String, dataJson: String) {
        this.httpStatus = httpStatus
        this.code = code
        this.message = message
        this.dataJson = dataJson
    }
}

struct HttpRequestData {
    let method: String
    let path: String
    let body: String

    public init(method: String, path: String, body: String) {
        this.method = method
        this.path = path
        this.body = body
    }
}

struct HttpResponseData {
    let statusCode: UInt16
    let contentType: String
    let body: String

    public init(statusCode: UInt16, contentType: String, body: String) {
        this.statusCode = statusCode
        this.contentType = contentType
        this.body = body
    }
}

class LanRoom {
    let roomId: String
    let blackToken: String
    var whiteToken: ?String = None
    var session: GameSession

    public init(roomId: String, blackToken: String) {
        this.roomId = roomId
        this.blackToken = blackToken
        this.session = GameSession()
    }

    public func isReady(): Bool {
        return whiteToken.isSome()
    }

    public func connectedPlayers(): Int64 {
        if (whiteToken.isSome()) {
            return 2
        }
        return 1
    }
}

class GomokuHttpApp {
    private var localSession: ?GameSession = None
    private var aiSession: ?GameSession = None
    private var rooms = HashMap<String, LanRoom>()
    private var nextRoomNumber: Int64 = 100001
    private var nextTokenNumber: Int64 = 1

    public init() {}

    public func health(): ApiResult {
        return ApiResult(200u16, 0, "ok", "{\"status\":\"ok\"}")
    }

    public func startLocal(): ApiResult {
        let session = GameSession()
        localSession = Some(session)
        return ApiResult(200u16, 0, "ok", sessionToJson(session, None, None, None, "local"))
    }

    public func moveLocal(x: Int64, y: Int64): ApiResult {
        match (localSession) {
            case Some(session) =>
                let moveResult = GameRules.placeStone(session, x, y)
                let data = sessionToJson(session, moveResult.move, moveResult.move, None, "local")
                if (moveResult.success) {
                    return ApiResult(200u16, 0, "ok", data)
                }
                return ApiResult(400u16, 2001, moveResult.message, data)
            case None =>
                return ApiResult(404u16, 1001, "local session not started", "null")
        }
    }

    public func startAi(): ApiResult {
        let session = GameSession()
        aiSession = Some(session)
        return ApiResult(200u16, 0, "ok", sessionToJson(session, None, None, None, "ai"))
    }

    public func moveAi(x: Int64, y: Int64): ApiResult {
        match (aiSession) {
            case Some(session) =>
                let playerMove = GameRules.placeStone(session, x, y)
                if (!playerMove.success) {
                    return ApiResult(400u16, 2001, playerMove.message, sessionToJson(session, playerMove.move, playerMove.move, None, "ai"))
                }

                var aiMove: ?Move = None
                if (!session.finished) {
                    match (AiEngine.chooseMove(session)) {
                        case Some(point) =>
                            let aiMoveResult = GameRules.placeStone(session, point.x, point.y)
                            if (!aiMoveResult.success) {
                                return ApiResult(500u16, 3001, aiMoveResult.message, "null")
                            }
                            aiMove = aiMoveResult.move
                        case None =>
                            return ApiResult(500u16, 3002, "ai failed to choose move", "null")
                    }
                }

                var lastMove = playerMove.move
                if (let Some(finalMove) <- aiMove) {
                    lastMove = Some(finalMove)
                }
                return ApiResult(200u16, 0, "ok", sessionToJson(session, lastMove, playerMove.move, aiMove, "ai"))
            case None =>
                return ApiResult(404u16, 1001, "ai session not started", "null")
        }
    }

    public func createRoom(): ApiResult {
        let roomId = generateRoomId()
        let token = generatePlayerToken()
        let room = LanRoom(roomId, token)
        rooms[roomId] = room
        return ApiResult(200u16, 0, "ok", roomToJson(room, token))
    }

    public func joinRoom(roomId: String): ApiResult {
        match (rooms.get(roomId)) {
            case Some(room) =>
                if (room.whiteToken.isSome()) {
                    return ApiResult(409u16, 4002, "room already full", "null")
                }
                let token = generatePlayerToken()
                room.whiteToken = Some(token)
                return ApiResult(200u16, 0, "ok", roomToJson(room, token))
            case None =>
                return ApiResult(404u16, 4001, "room not found", "null")
        }
    }

    public func getRoomState(roomId: String, playerToken: String): ApiResult {
        match (rooms.get(roomId)) {
            case Some(room) =>
                if (!isValidPlayer(room, playerToken)) {
                    return ApiResult(403u16, 4005, "invalid player token", "null")
                }
                return ApiResult(200u16, 0, "ok", roomToJson(room, playerToken))
            case None =>
                return ApiResult(404u16, 4001, "room not found", "null")
        }
    }

    public func moveRoom(roomId: String, playerToken: String, x: Int64, y: Int64): ApiResult {
        match (rooms.get(roomId)) {
            case Some(room) =>
                match (stoneForPlayer(room, playerToken)) {
                    case Some(playerStone) =>
                        if (!room.isReady()) {
                            return ApiResult(409u16, 4003, "room waiting for opponent", roomToJson(room, playerToken))
                        }
                        if (room.session.currentPlayer != playerStone) {
                            return ApiResult(409u16, 4004, "not your turn", roomToJson(room, playerToken))
                        }
                        let moveResult = GameRules.placeStone(room.session, x, y)
                        let data = roomToJson(room, playerToken, lastMove: moveResult.move)
                        if (moveResult.success) {
                            return ApiResult(200u16, 0, "ok", data)
                        }
                        return ApiResult(400u16, 2001, moveResult.message, data)
                    case None =>
                        return ApiResult(403u16, 4005, "invalid player token", "null")
                }
            case None =>
                return ApiResult(404u16, 4001, "room not found", "null")
        }
    }

    public func restartRoom(roomId: String, playerToken: String): ApiResult {
        match (rooms.get(roomId)) {
            case Some(room) =>
                if (!isValidPlayer(room, playerToken)) {
                    return ApiResult(403u16, 4005, "invalid player token", "null")
                }
                room.session = GameSession()
                return ApiResult(200u16, 0, "ok", roomToJson(room, playerToken))
            case None =>
                return ApiResult(404u16, 4001, "room not found", "null")
        }
    }

    private func generateRoomId(): String {
        let value = nextRoomNumber
        nextRoomNumber += 1
        return "${value}"
    }

    private func generatePlayerToken(): String {
        let value = nextTokenNumber
        nextTokenNumber += 1
        return "player-${value}"
    }

    private func isValidPlayer(room: LanRoom, playerToken: String): Bool {
        return stoneForPlayer(room, playerToken).isSome()
    }
}

class GomokuServer {
    private let app: GomokuHttpApp
    private let host: String
    private let port: UInt16

    public init(app: GomokuHttpApp, host: String, port: UInt16) {
        this.app = app
        this.host = host
        this.port = port
    }

    public func serve(): Unit {
        let listener = TcpServerSocket(bindAt: port)
        listener.bind()
        println("gomoku http server started at http://${host}:${port}")

        while (true) {
            let socket = listener.accept()
            try {
                handleClient(socket)
            } catch (e: Exception) {
                try {
                    writePlain(socket, 500u16, "internal server error")
                } catch (_: Exception) {
                    ()
                }
            } finally {
                socket.close()
            }
        }
    }

    private func handleClient(socket: TcpSocket): Unit {
        match (readRequest(socket)) {
            case Some(request) =>
                let response = routeRequest(request)
                writeResponse(socket, response)
            case None =>
                writePlain(socket, 400u16, "bad request")
        }
    }

    private func routeRequest(request: HttpRequestData): HttpResponseData {
        if (request.path == "/" || request.path == "/index.html") {
            return serveFile(WEB_INDEX_PATH, "text/html; charset=utf-8")
        }
        if (request.path == "/styles.css") {
            return serveFile(WEB_STYLE_PATH, "text/css; charset=utf-8")
        }
        if (request.path == "/app.js") {
            return serveFile(WEB_APP_PATH, "application/javascript; charset=utf-8")
        }
        if (request.path == "/api/health") {
            return apiResponse(ensureMethod(request, "GET", app.health()))
        }
        if (request.path == "/api/local/start") {
            return apiResponse(ensureMethod(request, "POST", app.startLocal()))
        }
        if (request.path == "/api/local/move") {
            if (request.method != "POST") {
                return apiResponse(ApiResult(405u16, 1003, "method not allowed", "null"))
            }
            return apiResponse(app.moveLocal(extractJsonInt(request.body, "x"), extractJsonInt(request.body, "y")))
        }
        if (request.path == "/api/ai/start") {
            return apiResponse(ensureMethod(request, "POST", app.startAi()))
        }
        if (request.path == "/api/ai/move") {
            if (request.method != "POST") {
                return apiResponse(ApiResult(405u16, 1003, "method not allowed", "null"))
            }
            return apiResponse(app.moveAi(extractJsonInt(request.body, "x"), extractJsonInt(request.body, "y")))
        }
        if (request.path == "/api/room/create") {
            return apiResponse(ensureMethod(request, "POST", app.createRoom()))
        }
        if (request.path == "/api/room/join") {
            if (request.method != "POST") {
                return apiResponse(ApiResult(405u16, 1003, "method not allowed", "null"))
            }
            return apiResponse(app.joinRoom(extractJsonString(request.body, "roomId")))
        }
        if (request.path == "/api/room/state") {
            if (request.method != "POST") {
                return apiResponse(ApiResult(405u16, 1003, "method not allowed", "null"))
            }
            return apiResponse(app.getRoomState(
                extractJsonString(request.body, "roomId"),
                extractJsonString(request.body, "playerToken")
            ))
        }
        if (request.path == "/api/room/move") {
            if (request.method != "POST") {
                return apiResponse(ApiResult(405u16, 1003, "method not allowed", "null"))
            }
            return apiResponse(app.moveRoom(
                extractJsonString(request.body, "roomId"),
                extractJsonString(request.body, "playerToken"),
                extractJsonInt(request.body, "x"),
                extractJsonInt(request.body, "y")
            ))
        }
        if (request.path == "/api/room/restart") {
            if (request.method != "POST") {
                return apiResponse(ApiResult(405u16, 1003, "method not allowed", "null"))
            }
            return apiResponse(app.restartRoom(
                extractJsonString(request.body, "roomId"),
                extractJsonString(request.body, "playerToken")
            ))
        }
        return HttpResponseData(404u16, "text/plain; charset=utf-8", "not found")
    }

    private func ensureMethod(request: HttpRequestData, method: String, result: ApiResult): ApiResult {
        if (request.method != method) {
            return ApiResult(405u16, 1003, "method not allowed", "null")
        }
        return result
    }

    private func apiResponse(apiResult: ApiResult): HttpResponseData {
        return HttpResponseData(
            apiResult.httpStatus,
            "application/json; charset=utf-8",
            apiEnvelope(apiResult.code, apiResult.message, apiResult.dataJson)
        )
    }

    private func serveFile(path: String, contentType: String): HttpResponseData {
        try {
            return HttpResponseData(200u16, contentType, String.fromUtf8(File.readFrom(path)))
        } catch (e: Exception) {
            return HttpResponseData(404u16, "text/plain; charset=utf-8", "not found")
        }
    }

    private func writePlain(socket: TcpSocket, statusCode: UInt16, body: String): Unit {
        writeResponse(socket, HttpResponseData(statusCode, "text/plain; charset=utf-8", body))
    }
}

func createGomokuServer(app: GomokuHttpApp, host: String, port: UInt16): GomokuServer {
    return GomokuServer(app, host, port)
}

private func readRequest(socket: TcpSocket): ?HttpRequestData {
    let bytes = ArrayList<Byte>()
    let buffer = Array<Byte>(HTTP_BUFFER_SIZE, repeat: 0)
    var headerEnd = -1
    var contentLength = 0

    while (true) {
        let readLen = socket.read(buffer)
        if (readLen <= 0) {
            break
        }
        bytes.add(all: buffer[0..readLen])

        if (headerEnd < 0) {
            headerEnd = indexOfHeaderEnd(bytes)
            if (headerEnd >= 0) {
                let headerText = unsafe { String.fromUtf8Unchecked(bytes.getRawArray()[0..headerEnd]) }
                contentLength = parseContentLength(headerText)
            }
        }

        if (headerEnd >= 0 && bytes.size >= headerEnd + 4 + contentLength) {
            break
        }
    }

    if (headerEnd < 0) {
        return None
    }

    let headerText = unsafe { String.fromUtf8Unchecked(bytes.getRawArray()[0..headerEnd]) }
    let lines = headerText.split("\r\n")
    if (lines.size == 0) {
        return None
    }

    let requestLine = lines[0].split(" ")
    if (requestLine.size < 2) {
        return None
    }

    let bodyStart = headerEnd + 4
    let bodyEnd = bodyStart + contentLength
    let body = if (contentLength > 0) {
        unsafe { String.fromUtf8Unchecked(bytes.getRawArray()[bodyStart..bodyEnd]) }
    } else {
        ""
    }

    return Some(HttpRequestData(
        requestLine[0],
        normalizePath(requestLine[1]),
        body
    ))
}

private func normalizePath(rawPath: String): String {
    let path = rawPath.split("?")
    if (path.size == 0) {
        return rawPath
    }
    return path[0]
}

private func parseContentLength(headerText: String): Int64 {
    let lines = headerText.split("\r\n")
    var index = 1
    while (index < lines.size) {
        let line = lines[index]
        if (line.startsWith("Content-Length:") || line.startsWith("content-length:")) {
            let parts = line.split(":")
            if (parts.size >= 2) {
                return parseInt(trimAscii(parts[1]))
            }
        }
        index += 1
    }
    return 0
}

private func indexOfHeaderEnd(bytes: ArrayList<Byte>): Int64 {
    if (bytes.size < 4) {
        return -1
    }
    unsafe {
        let raw = bytes.getRawArray()
        var index = 0
        while (index <= bytes.size - 4) {
            if (raw[index] == b'\r' && raw[index + 1] == b'\n' && raw[index + 2] == b'\r' && raw[index + 3] == b'\n') {
                return index
            }
            index += 1
        }
    }
    return -1
}

private func writeResponse(socket: TcpSocket, response: HttpResponseData): Unit {
    let bodyBytes = response.body.toArray()
    let header = "HTTP/1.1 ${response.statusCode} ${statusText(response.statusCode)}\r\n" +
        "Content-Type: ${response.contentType}\r\n" +
        "Content-Length: ${bodyBytes.size}\r\n" +
        "Connection: close\r\n\r\n"
    socket.write(header.toArray())
    if (bodyBytes.size > 0) {
        socket.write(bodyBytes)
    }
}

private func statusText(statusCode: UInt16): String {
    if (statusCode == 200u16) {
        return "OK"
    }
    if (statusCode == 400u16) {
        return "Bad Request"
    }
    if (statusCode == 403u16) {
        return "Forbidden"
    }
    if (statusCode == 404u16) {
        return "Not Found"
    }
    if (statusCode == 405u16) {
        return "Method Not Allowed"
    }
    if (statusCode == 409u16) {
        return "Conflict"
    }
    return "Internal Server Error"
}

private func apiEnvelope(code: Int64, message: String, dataJson: String): String {
    return "{" +
        "\"code\":${code}," +
        "\"message\":${jsonString(message)}," +
        "\"data\":${dataJson}" +
        "}"
}

private func roomToJson(room: LanRoom, playerToken: String, lastMove!: ?Move = None): String {
    let effectiveLastMove = match (lastMove) {
        case Some(value) => Some(value)
        case None => latestMove(room.session)
    }
    return "{" +
        "\"mode\":\"lan\"," +
        "\"board\":${boardToJson(room.session.board)}," +
        "\"currentPlayer\":${jsonString(stoneName(room.session.currentPlayer))}," +
        "\"gameResult\":${jsonString(resultName(room.session.result))}," +
        "\"finished\":${boolJson(room.session.finished)}," +
        "\"lastMove\":${moveToJson(effectiveLastMove)}," +
        "\"playerMove\":null," +
        "\"aiMove\":null," +
        "\"roomId\":${jsonString(room.roomId)}," +
        "\"playerToken\":${jsonString(playerToken)}," +
        "\"playerRole\":${jsonString(roomRole(room, playerToken))}," +
        "\"playerStone\":${jsonString(playerStoneName(stoneForPlayer(room, playerToken)))}," +
        "\"connectedPlayers\":${room.connectedPlayers()}," +
        "\"connectionStatus\":${jsonString(roomConnectionStatus(room))}," +
        "\"canMove\":${boolJson(roomCanMove(room, playerToken))}," +
        "\"waitingForOpponent\":${boolJson(!room.isReady())}" +
        "}"
}

private func sessionToJson(session: GameSession, lastMove: ?Move, playerMove: ?Move, aiMove: ?Move, mode: String): String {
    return "{" +
        "\"mode\":${jsonString(mode)}," +
        "\"board\":${boardToJson(session.board)}," +
        "\"currentPlayer\":${jsonString(stoneName(session.currentPlayer))}," +
        "\"gameResult\":${jsonString(resultName(session.result))}," +
        "\"finished\":${boolJson(session.finished)}," +
        "\"lastMove\":${moveToJson(lastMove)}," +
        "\"playerMove\":${moveToJson(playerMove)}," +
        "\"aiMove\":${moveToJson(aiMove)}" +
        "}"
}

private func latestMove(session: GameSession): ?Move {
    if (session.history.size == 0) {
        return None
    }
    return Some(session.history[session.history.size - 1])
}

private func boardToJson(board: Board): String {
    var json = "["
    var y = 0
    while (y < BOARD_SIZE) {
        if (y > 0) {
            json += ","
        }
        json += "["
        var x = 0
        while (x < BOARD_SIZE) {
            if (x > 0) {
                json += ","
            }
            json += "${stoneCode(board.getStone(x, y))}"
            x += 1
        }
        json += "]"
        y += 1
    }
    json += "]"
    return json
}

private func moveToJson(move: ?Move): String {
    match (move) {
        case Some(value) =>
            return "{" +
                "\"x\":${value.x}," +
                "\"y\":${value.y}," +
                "\"stone\":${jsonString(stoneName(value.stone))}," +
                "\"step\":${value.step}" +
                "}"
        case None =>
            return "null"
    }
}

private func stoneCode(stone: Stone): Int64 {
    match (stone) {
        case Stone.Black => return 1
        case Stone.White => return 2
        case _ => return 0
    }
}

private func stoneForPlayer(room: LanRoom, playerToken: String): ?Stone {
    if (playerToken == room.blackToken) {
        return Some(Stone.Black)
    }
    if (let Some(whiteToken) <- room.whiteToken) {
        if (playerToken == whiteToken) {
            return Some(Stone.White)
        }
    }
    return None
}

private func roomRole(room: LanRoom, playerToken: String): String {
    if (playerToken == room.blackToken) {
        return "host"
    }
    if (let Some(whiteToken) <- room.whiteToken) {
        if (playerToken == whiteToken) {
            return "guest"
        }
    }
    return "unknown"
}

private func roomConnectionStatus(room: LanRoom): String {
    if (room.isReady()) {
        return "Connected"
    }
    return "Waiting"
}

private func roomCanMove(room: LanRoom, playerToken: String): Bool {
    if (!room.isReady() || room.session.finished) {
        return false
    }
    match (stoneForPlayer(room, playerToken)) {
        case Some(stone) => return room.session.currentPlayer == stone
        case None => return false
    }
}

private func stoneName(stone: Stone): String {
    match (stone) {
        case Stone.Black => return "Black"
        case Stone.White => return "White"
        case _ => return "Empty"
    }
}

private func playerStoneName(stone: ?Stone): String {
    match (stone) {
        case Some(value) => return stoneName(value)
        case None => return "Empty"
    }
}

private func resultName(result: GameResult): String {
    match (result) {
        case GameResult.BlackWin => return "BlackWin"
        case GameResult.WhiteWin => return "WhiteWin"
        case GameResult.Draw => return "Draw"
        case _ => return "Playing"
    }
}

private func jsonString(value: String): String {
    var result = "\""
    var index = 0
    while (index < value.size) {
        let ch = value[index]
        if (ch == b'\\') {
            result += "\\\\"
        } else if (ch == b'"') {
            result += "\\\""
        } else if (ch == b'\n') {
            result += "\\n"
        } else if (ch == b'\r') {
            result += "\\r"
        } else if (ch == b'\t') {
            result += "\\t"
        } else {
            result += unsafe { String.fromUtf8Unchecked([ch]) }
        }
        index += 1
    }
    result += "\""
    return result
}

private func boolJson(value: Bool): String {
    if (value) {
        return "true"
    }
    return "false"
}

private func extractJsonString(body: String, key: String): String {
    let tail = tailAfterKey(body, key)
    var index = skipWhitespace(tail, 0)
    if (tail[index] != b'"') {
        throw Exception("invalid json")
    }
    index += 1
    let start = index
    while (index < tail.size && tail[index] != b'"') {
        index += 1
    }
    return stringSlice(tail, start, index)
}

private func extractJsonInt(body: String, key: String): Int64 {
    let tail = tailAfterKey(body, key)
    let start = skipWhitespace(tail, 0)
    var end = start
    while (end < tail.size && isNumberByte(tail[end])) {
        end += 1
    }
    return parseInt(stringSlice(tail, start, end))
}

private func tailAfterKey(body: String, key: String): String {
    let marker = "\"${key}\":"
    let parts = body.split(marker)
    if (parts.size < 2) {
        throw Exception("missing key")
    }
    return parts[1]
}

private func trimAscii(text: String): String {
    let start = skipWhitespace(text, 0)
    var end = text.size
    while (end > start && isWhitespace(text[end - 1])) {
        end -= 1
    }
    return stringSlice(text, start, end)
}

private func skipWhitespace(text: String, start: Int64): Int64 {
    var index = start
    while (index < text.size && isWhitespace(text[index])) {
        index += 1
    }
    return index
}

private func isWhitespace(value: Byte): Bool {
    return value == b' ' || value == b'\n' || value == b'\r' || value == b'\t'
}

private func isNumberByte(value: Byte): Bool {
    return value == b'-' || (value >= b'0' && value <= b'9')
}

private func parseInt(text: String): Int64 {
    var index = 0
    var sign = 1
    if (text.size > 0 && text[0] == b'-') {
        sign = -1
        index = 1
    }

    var value = 0
    while (index < text.size) {
        let digit = text[index]
        if (digit < b'0' || digit > b'9') {
            break
        }
        value = value * 10 + Int64(digit - b'0')
        index += 1
    }
    return value * sign
}

private func stringSlice(text: String, start: Int64, end: Int64): String {
    return unsafe { String.fromUtf8Unchecked(text.toArray()[start..end]) }
}
