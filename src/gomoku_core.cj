package finalwork

import std.collection.*

// 统一的棋盘常量，避免业务逻辑中散落魔法数字。
const BOARD_SIZE: Int64 = 15
const BOARD_CELL_COUNT: Int64 = BOARD_SIZE * BOARD_SIZE
const WIN_STONE_COUNT: Int64 = 5

enum Stone <: Equatable<Stone> {
    | Empty
    | Black
    | White

    public operator func ==(right: Stone): Bool {
        match (this) {
            case Empty => match (right) {
                case Empty => true
                case _ => false
            }
            case Black => match (right) {
                case Black => true
                case _ => false
            }
            case White => match (right) {
                case White => true
                case _ => false
            }
        }
    }

    public operator func !=(right: Stone): Bool {
        return !(this == right)
    }

    // 切换当前落子方。Empty 仅用于棋盘空位，不参与轮换。
    public func opposite(): Stone {
        match (this) {
            case Black => White
            case White => Black
            case _ => Empty
        }
    }
}

enum GameResult <: Equatable<GameResult> {
    | Playing
    | BlackWin
    | WhiteWin
    | Draw

    public operator func ==(right: GameResult): Bool {
        match (this) {
            case Playing => match (right) {
                case Playing => true
                case _ => false
            }
            case BlackWin => match (right) {
                case BlackWin => true
                case _ => false
            }
            case WhiteWin => match (right) {
                case WhiteWin => true
                case _ => false
            }
            case Draw => match (right) {
                case Draw => true
                case _ => false
            }
        }
    }

    public operator func !=(right: GameResult): Bool {
        return !(this == right)
    }
}

// 一次有效落子的领域记录。
struct Move {
    let x: Int64
    let y: Int64
    let stone: Stone
    let step: Int64

    public init(x: Int64, y: Int64, stone: Stone, step: Int64) {
        this.x = x
        this.y = y
        this.stone = stone
        this.step = step
    }
}

// 纯逻辑层返回的执行结果，便于单元测试直接断言。
struct PlaceMoveResult {
    let success: Bool
    let message: String
    let move: Option<Move>
    let result: GameResult

    public init(success: Bool, message: String, move: Option<Move>, result: GameResult) {
        this.success = success
        this.message = message
        this.move = move
        this.result = result
    }
}

// Board 只负责棋盘数据存取，不承担规则判定。
class Board {
    let size: Int64
    var cells: Array<Stone>

    public init() {
        this.size = BOARD_SIZE
        this.cells = Array<Stone>(BOARD_CELL_COUNT, repeat: Stone.Empty)
    }

    private func toIndex(x: Int64, y: Int64): Int64 {
        return y * size + x
    }

    public func getStone(x: Int64, y: Int64): Stone {
        return cells[toIndex(x, y)]
    }

    public func setStone(x: Int64, y: Int64, stone: Stone): Unit {
        cells[toIndex(x, y)] = stone
    }

    public func isEmptyAt(x: Int64, y: Int64): Bool {
        return getStone(x, y) == Stone.Empty
    }

    public func isFull(): Bool {
        var index = 0
        while (index < cells.size) {
            if (cells[index] == Stone.Empty) {
                return false
            }
            index += 1
        }
        return true
    }
}

// GameSession 是当前对局的聚合根，保存唯一真实状态。
class GameSession {
    var board: Board
    var currentPlayer: Stone
    var history: ArrayList<Move>
    var result: GameResult
    var finished: Bool

    public init() {
        this.board = Board()
        this.currentPlayer = Stone.Black
        this.history = ArrayList<Move>()
        this.result = GameResult.Playing
        this.finished = false
    }
}

// GameRules 集中实现落子合法性、胜负判定与回合流转。
struct GameRules {
    public static func isValidCoordinate(x: Int64, y: Int64): Bool {
        return x >= 0 && x < BOARD_SIZE && y >= 0 && y < BOARD_SIZE
    }

    public static func isPositionEmpty(board: Board, x: Int64, y: Int64): Bool {
        if (!isValidCoordinate(x, y)) {
            return false
        }
        return board.isEmptyAt(x, y)
    }

    public static func placeStone(session: GameSession, x: Int64, y: Int64): PlaceMoveResult {
        if (session.finished) {
            return PlaceMoveResult(
                false,
                "game already finished",
                None,
                session.result
            )
        }

        if (!isValidCoordinate(x, y)) {
            return PlaceMoveResult(
                false,
                "invalid coordinate",
                None,
                session.result
            )
        }

        if (!session.board.isEmptyAt(x, y)) {
            return PlaceMoveResult(
                false,
                "position already occupied",
                None,
                session.result
            )
        }

        let stone = session.currentPlayer
        let step = session.history.size + 1
        let move = Move(x, y, stone, step)

        session.board.setStone(x, y, stone)
        session.history.add(move)

        if (hasFiveInRow(session.board, x, y, stone)) {
            session.finished = true
            session.result = resultForStone(stone)
        } else if (session.board.isFull()) {
            session.finished = true
            session.result = GameResult.Draw
        } else {
            switchTurn(session)
        }

        return PlaceMoveResult(
            true,
            "ok",
            Some(move),
            session.result
        )
    }

    public static func hasFiveInRow(board: Board, x: Int64, y: Int64, stone: Stone): Bool {
        if (stone == Stone.Empty) {
            return false
        }

        return countConnected(board, x, y, 1, 0, stone) + countConnected(board, x, y, -1, 0, stone) - 1 >= WIN_STONE_COUNT ||
            countConnected(board, x, y, 0, 1, stone) + countConnected(board, x, y, 0, -1, stone) - 1 >= WIN_STONE_COUNT ||
            countConnected(board, x, y, 1, 1, stone) + countConnected(board, x, y, -1, -1, stone) - 1 >= WIN_STONE_COUNT ||
            countConnected(board, x, y, 1, -1, stone) + countConnected(board, x, y, -1, 1, stone) - 1 >= WIN_STONE_COUNT
    }

    public static func switchTurn(session: GameSession): Unit {
        session.currentPlayer = session.currentPlayer.opposite()
    }

    private static func countConnected(board: Board, startX: Int64, startY: Int64, dx: Int64, dy: Int64, stone: Stone): Int64 {
        var count = 0
        var x = startX
        var y = startY

        while (isValidCoordinate(x, y) && board.getStone(x, y) == stone) {
            count += 1
            x += dx
            y += dy
        }

        return count
    }

    private static func resultForStone(stone: Stone): GameResult {
        match (stone) {
            case Black => return GameResult.BlackWin
            case White => return GameResult.WhiteWin
            case _ => return GameResult.Playing
        }
    }
}
