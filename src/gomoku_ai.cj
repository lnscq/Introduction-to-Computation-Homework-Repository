package finalwork

// 简单坐标对象，复用于 AI 选点与请求参数解析。
struct Point {
    let x: Int64
    let y: Int64

    public init(x: Int64, y: Int64) {
        this.x = x
        this.y = y
    }
}

enum AiDifficulty <: Equatable<AiDifficulty> {
    | Easy
    | Normal

    public operator func ==(right: AiDifficulty): Bool {
        match (this) {
            case Easy => match (right) {
                case Easy => true
                case _ => false
            }
            case Normal => match (right) {
                case Normal => true
                case _ => false
            }
        }
    }

    public operator func !=(right: AiDifficulty): Bool {
        return !(this == right)
    }
}

struct PatternSummary {
    let five: Int64
    let openFour: Int64
    let blockedFour: Int64
    let openThree: Int64
    let sleepThree: Int64
    let openTwo: Int64

    public init(
        five: Int64,
        openFour: Int64,
        blockedFour: Int64,
        openThree: Int64,
        sleepThree: Int64,
        openTwo: Int64
    ) {
        this.five = five
        this.openFour = openFour
        this.blockedFour = blockedFour
        this.openThree = openThree
        this.sleepThree = sleepThree
        this.openTwo = openTwo
    }
}

// 课程项目使用的启发式 AI，不依赖任何外部服务。
const BOARD_CENTER: Int64 = BOARD_SIZE / 2

struct AiEngine {
    public static func chooseMove(session: GameSession): ?Point {
        return chooseBestMoveByDifficulty(session, session.currentPlayer, AiDifficulty.Normal)
    }

    public static func chooseMoveByDifficulty(session: GameSession, difficulty: AiDifficulty): ?Point {
        return chooseBestMoveByDifficulty(session, session.currentPlayer, difficulty)
    }

    public static func chooseBestMove(session: GameSession, aiStone: Stone): ?Point {
        return chooseBestMoveByDifficulty(session, aiStone, AiDifficulty.Normal)
    }

    public static func chooseBestMoveByDifficulty(session: GameSession, aiStone: Stone, difficulty: AiDifficulty): ?Point {
        if (session.finished || aiStone == Stone.Empty) {
            return None
        }

        if (session.history.size == 0 && session.board.isEmptyAt(BOARD_CENTER, BOARD_CENTER)) {
            return Some(Point(BOARD_CENTER, BOARD_CENTER))
        }

        let enemyStone = aiStone.opposite()
        var winningMove: ?Point = None
        var winningCluster = -1
        var winningCenter = -1

        var forcedDefenseMove: ?Point = None
        var forcedDefenseCluster = -1
        var forcedDefenseCenter = -1

        var bestMove: ?Point = None
        var bestScore = -1000000000
        var bestCluster = -1
        var bestCenter = -1

        var hasCandidate = false
        var y = 0
        while (y < BOARD_SIZE) {
            var x = 0
            while (x < BOARD_SIZE) {
                if (isCandidateCell(session.board, x, y)) {
                    hasCandidate = true

                    let attack = analyzePoint(session.board, x, y, aiStone)
                    let defense = analyzePoint(session.board, x, y, enemyStone)
                    let cluster = clusterScore(session.board, x, y, aiStone)
                    let center = centerBonus(x, y)

                    if (attack.five > 0) {
                        if (!winningMove.isSome() || cluster > winningCluster || (cluster == winningCluster && center > winningCenter)) {
                            winningMove = Some(Point(x, y))
                            winningCluster = cluster
                            winningCenter = center
                        }
                    } else if (defense.five > 0) {
                        if (!forcedDefenseMove.isSome() || cluster > forcedDefenseCluster || (cluster == forcedDefenseCluster && center > forcedDefenseCenter)) {
                            forcedDefenseMove = Some(Point(x, y))
                            forcedDefenseCluster = cluster
                            forcedDefenseCenter = center
                        }
                    }

                    var score = 0
                    match (difficulty) {
                        case Easy => score = evaluatePoint(session.board, x, y, aiStone, enemyStone)
                        case Normal => score = evaluateNormalMove(session.board, x, y, aiStone, enemyStone)
                    }

                    if (!bestMove.isSome() || score > bestScore || (score == bestScore && cluster > bestCluster) ||
                        (score == bestScore && cluster == bestCluster && center > bestCenter)) {
                        bestMove = Some(Point(x, y))
                        bestScore = score
                        bestCluster = cluster
                        bestCenter = center
                    }
                }
                x += 1
            }
            y += 1
        }

        if (winningMove.isSome()) {
            return winningMove
        }
        if (forcedDefenseMove.isSome()) {
            return forcedDefenseMove
        }
        if (bestMove.isSome()) {
            return bestMove
        }
        if (!hasCandidate) {
            return findFirstEmpty(session.board)
        }
        return None
    }

    public static func evaluatePoint(board: Board, x: Int64, y: Int64, selfStone: Stone, enemyStone: Stone): Int64 {
        if (!GameRules.isPositionEmpty(board, x, y)) {
            return -1
        }

        let attack = analyzePoint(board, x, y, selfStone)
        let defense = analyzePoint(board, x, y, enemyStone)
        let cluster = clusterScore(board, x, y, selfStone)
        let center = centerBonus(x, y)

        return attackScore(attack) + defenseScore(defense) + cluster * 10 + center
    }

    private static func evaluateNormalMove(board: Board, x: Int64, y: Int64, selfStone: Stone, enemyStone: Stone): Int64 {
        let currentScore = evaluatePoint(board, x, y, selfStone, enemyStone)

        board.setStone(x, y, selfStone)
        let enemyReplyThreat = findBestThreatScore(board, enemyStone)
        let selfFollowUpThreat = findBestThreatScore(board, selfStone)
        board.setStone(x, y, Stone.Empty)

        return currentScore * 4 + selfFollowUpThreat * 2 - enemyReplyThreat * 3
    }

    private static func findBestThreatScore(board: Board, stone: Stone): Int64 {
        var best = 0
        var y = 0
        while (y < BOARD_SIZE) {
            var x = 0
            while (x < BOARD_SIZE) {
                if (isCandidateCell(board, x, y)) {
                    let score = attackScore(analyzePoint(board, x, y, stone))
                    if (score > best) {
                        best = score
                    }
                }
                x += 1
            }
            y += 1
        }
        return best
    }

    private static func analyzePoint(board: Board, x: Int64, y: Int64, stone: Stone): PatternSummary {
        if (stone == Stone.Empty || !GameRules.isPositionEmpty(board, x, y)) {
            return PatternSummary(0, 0, 0, 0, 0, 0)
        }

        board.setStone(x, y, stone)

        var five = 0
        var openFour = 0
        var blockedFour = 0
        var openThree = 0
        var sleepThree = 0
        var openTwo = 0

        let horizontalPattern = classifyDirection(buildLine(board, x, y, 1, 0, stone), 5)
        if (horizontalPattern == 5) {
            five += 1
        } else if (horizontalPattern == 4) {
            openFour += 1
        } else if (horizontalPattern == 3) {
            blockedFour += 1
        } else if (horizontalPattern == 2) {
            openThree += 1
        } else if (horizontalPattern == 1) {
            sleepThree += 1
        } else if (horizontalPattern == 0) {
            openTwo += 1
        }

        let verticalPattern = classifyDirection(buildLine(board, x, y, 0, 1, stone), 5)
        if (verticalPattern == 5) {
            five += 1
        } else if (verticalPattern == 4) {
            openFour += 1
        } else if (verticalPattern == 3) {
            blockedFour += 1
        } else if (verticalPattern == 2) {
            openThree += 1
        } else if (verticalPattern == 1) {
            sleepThree += 1
        } else if (verticalPattern == 0) {
            openTwo += 1
        }

        let diagDownPattern = classifyDirection(buildLine(board, x, y, 1, 1, stone), 5)
        if (diagDownPattern == 5) {
            five += 1
        } else if (diagDownPattern == 4) {
            openFour += 1
        } else if (diagDownPattern == 3) {
            blockedFour += 1
        } else if (diagDownPattern == 2) {
            openThree += 1
        } else if (diagDownPattern == 1) {
            sleepThree += 1
        } else if (diagDownPattern == 0) {
            openTwo += 1
        }

        let diagUpPattern = classifyDirection(buildLine(board, x, y, 1, -1, stone), 5)
        if (diagUpPattern == 5) {
            five += 1
        } else if (diagUpPattern == 4) {
            openFour += 1
        } else if (diagUpPattern == 3) {
            blockedFour += 1
        } else if (diagUpPattern == 2) {
            openThree += 1
        } else if (diagUpPattern == 1) {
            sleepThree += 1
        } else if (diagUpPattern == 0) {
            openTwo += 1
        }

        board.setStone(x, y, Stone.Empty)
        return PatternSummary(five, openFour, blockedFour, openThree, sleepThree, openTwo)
    }

    private static func classifyDirection(line: Array<Int64>, center: Int64): Int64 {
        if (containsFive(line, center)) {
            return 5
        }
        if (containsOpenFour(line, center)) {
            return 4
        }
        if (containsBlockedFour(line, center)) {
            return 3
        }
        if (containsOpenThree(line, center)) {
            return 2
        }
        if (containsSleepThree(line, center)) {
            return 1
        }
        if (containsOpenTwo(line, center)) {
            return 0
        }
        return -1
    }

    private static func buildLine(board: Board, x: Int64, y: Int64, dx: Int64, dy: Int64, stone: Stone): Array<Int64> {
        let line = Array<Int64>(11, repeat: -1)
        var offset = -5
        while (offset <= 5) {
            let index = offset + 5
            let cx = x + dx * offset
            let cy = y + dy * offset
            if (GameRules.isValidCoordinate(cx, cy)) {
                let cellStone = board.getStone(cx, cy)
                if (cellStone == stone) {
                    line[index] = 1
                } else if (cellStone == Stone.Empty) {
                    line[index] = 0
                } else {
                    line[index] = -1
                }
            }
            offset += 1
        }
        return line
    }

    private static func containsFive(line: Array<Int64>, center: Int64): Bool {
        var start = 0
        while (start <= 6) {
            if (windowContainsCenter(start, 5, center) && countValue(line, start, 5, 1) == 5) {
                return true
            }
            start += 1
        }
        return false
    }

    private static func containsOpenFour(line: Array<Int64>, center: Int64): Bool {
        var start = 0
        while (start <= 5) {
            if (windowContainsCenter(start, 6, center) &&
                line[start] == 0 &&
                line[start + 1] == 1 &&
                line[start + 2] == 1 &&
                line[start + 3] == 1 &&
                line[start + 4] == 1 &&
                line[start + 5] == 0) {
                return true
            }
            start += 1
        }
        return false
    }

    private static func containsBlockedFour(line: Array<Int64>, center: Int64): Bool {
        var start = 0
        while (start <= 6) {
            if (windowContainsCenter(start, 5, center) &&
                countValue(line, start, 5, -1) == 0 &&
                countValue(line, start, 5, 1) == 4 &&
                countValue(line, start, 5, 0) == 1) {
                return true
            }
            start += 1
        }
        return false
    }

    private static func containsOpenThree(line: Array<Int64>, center: Int64): Bool {
        var start = 0
        while (start <= 5) {
            if (windowContainsCenter(start, 6, center) && isOpenThreeWindow(line, start)) {
                return true
            }
            start += 1
        }
        return false
    }

    private static func containsSleepThree(line: Array<Int64>, center: Int64): Bool {
        var start = 0
        while (start <= 5) {
            if (windowContainsCenter(start, 6, center) && isSleepThreeWindow(line, start)) {
                return true
            }
            start += 1
        }
        return false
    }

    private static func containsOpenTwo(line: Array<Int64>, center: Int64): Bool {
        var start = 0
        while (start <= 5) {
            if (windowContainsCenter(start, 6, center) && isOpenTwoWindow(line, start)) {
                return true
            }
            start += 1
        }
        return false
    }

    private static func isOpenThreeWindow(line: Array<Int64>, start: Int64): Bool {
        if (countValue(line, start, 6, -1) > 0 || countValue(line, start, 6, 1) != 3 || countValue(line, start, 6, 0) != 3) {
            return false
        }
        return canCreateOpenFour(line, start)
    }

    private static func isSleepThreeWindow(line: Array<Int64>, start: Int64): Bool {
        if (countValue(line, start, 6, 1) != 3 || countValue(line, start, 6, 0) < 2 || countValue(line, start, 6, -1) > 1) {
            return false
        }
        if (isOpenThreeWindow(line, start)) {
            return false
        }
        return canCreateBlockedFour(line, start, 6)
    }

    private static func isOpenTwoWindow(line: Array<Int64>, start: Int64): Bool {
        if (countValue(line, start, 6, -1) > 0 || countValue(line, start, 6, 1) != 2 || countValue(line, start, 6, 0) != 4) {
            return false
        }

        var temp = Array<Int64>(6, repeat: 0)
        copyWindow(line, start, temp, 6)

        var index = 0
        while (index < 6) {
            if (temp[index] == 0) {
                temp[index] = 1
                if (isOpenThreeState(temp)) {
                    return true
                }
                temp[index] = 0
            }
            index += 1
        }
        return false
    }

    private static func isOpenThreeState(window: Array<Int64>): Bool {
        if (countArrayValue(window, 6, -1) > 0 || countArrayValue(window, 6, 1) != 3 || countArrayValue(window, 6, 0) != 3) {
            return false
        }
        return canCreateOpenFourOnState(window)
    }

    private static func canCreateOpenFour(line: Array<Int64>, start: Int64): Bool {
        var temp = Array<Int64>(6, repeat: 0)
        copyWindow(line, start, temp, 6)
        return canCreateOpenFourOnState(temp)
    }

    private static func canCreateOpenFourOnState(window: Array<Int64>): Bool {
        var index = 0
        while (index < 6) {
            if (window[index] == 0) {
                window[index] = 1
                if (window[0] == 0 && window[1] == 1 && window[2] == 1 && window[3] == 1 && window[4] == 1 && window[5] == 0) {
                    window[index] = 0
                    return true
                }
                window[index] = 0
            }
            index += 1
        }
        return false
    }

    private static func canCreateBlockedFour(line: Array<Int64>, start: Int64, length: Int64): Bool {
        var temp = Array<Int64>(length, repeat: 0)
        copyWindow(line, start, temp, length)

        var index = 0
        while (index < length) {
            if (temp[index] == 0) {
                temp[index] = 1
                if (hasBlockedFourState(temp, length)) {
                    temp[index] = 0
                    return true
                }
                temp[index] = 0
            }
            index += 1
        }
        return false
    }

    private static func hasBlockedFourState(window: Array<Int64>, length: Int64): Bool {
        if (length == 5) {
            return countArrayValue(window, 5, -1) == 0 && countArrayValue(window, 5, 1) == 4 && countArrayValue(window, 5, 0) == 1
        }

        var start = 0
        while (start <= length - 5) {
            if (countSubArrayValue(window, start, 5, -1) == 0 &&
                countSubArrayValue(window, start, 5, 1) == 4 &&
                countSubArrayValue(window, start, 5, 0) == 1) {
                return true
            }
            start += 1
        }
        return false
    }

    private static func copyWindow(source: Array<Int64>, start: Int64, target: Array<Int64>, length: Int64): Unit {
        var index = 0
        while (index < length) {
            target[index] = source[start + index]
            index += 1
        }
    }

    private static func countValue(values: Array<Int64>, start: Int64, length: Int64, target: Int64): Int64 {
        var count = 0
        var index = start
        while (index < start + length) {
            if (values[index] == target) {
                count += 1
            }
            index += 1
        }
        return count
    }

    private static func countArrayValue(values: Array<Int64>, length: Int64, target: Int64): Int64 {
        return countSubArrayValue(values, 0, length, target)
    }

    private static func countSubArrayValue(values: Array<Int64>, start: Int64, length: Int64, target: Int64): Int64 {
        var count = 0
        var index = start
        while (index < start + length) {
            if (values[index] == target) {
                count += 1
            }
            index += 1
        }
        return count
    }

    private static func windowContainsCenter(start: Int64, length: Int64, center: Int64): Bool {
        return start <= center && start + length - 1 >= center
    }

    private static func attackScore(pattern: PatternSummary): Int64 {
        var score = 0
        score += pattern.five * 1000000000
        score += pattern.openFour * 1000000
        score += pattern.blockedFour * 120000
        score += pattern.openThree * 18000
        score += pattern.sleepThree * 3200
        score += pattern.openTwo * 400

        if (pattern.openThree >= 2) {
            score += 60000
        }
        if (pattern.blockedFour >= 2) {
            score += 80000
        }
        return score
    }

    private static func defenseScore(pattern: PatternSummary): Int64 {
        var score = 0
        score += pattern.five * 900000000
        score += pattern.openFour * 1200000
        score += pattern.blockedFour * 160000
        score += pattern.openThree * 24000
        score += pattern.sleepThree * 4000
        score += pattern.openTwo * 500

        if (pattern.openThree >= 2) {
            score += 80000
        }
        return score
    }

    private static func isCandidateCell(board: Board, x: Int64, y: Int64): Bool {
        return GameRules.isPositionEmpty(board, x, y) && hasNearbyStone(board, x, y, 2)
    }

    private static func hasNearbyStone(board: Board, x: Int64, y: Int64, distance: Int64): Bool {
        var dy = -distance
        while (dy <= distance) {
            var dx = -distance
            while (dx <= distance) {
                if (!(dx == 0 && dy == 0)) {
                    let nx = x + dx
                    let ny = y + dy
                    if (GameRules.isValidCoordinate(nx, ny) && board.getStone(nx, ny) != Stone.Empty) {
                        return true
                    }
                }
                dx += 1
            }
            dy += 1
        }
        return false
    }

    private static func clusterScore(board: Board, x: Int64, y: Int64, selfStone: Stone): Int64 {
        var score = 0
        var dy = -2
        while (dy <= 2) {
            var dx = -2
            while (dx <= 2) {
                if (!(dx == 0 && dy == 0)) {
                    let nx = x + dx
                    let ny = y + dy
                    if (GameRules.isValidCoordinate(nx, ny)) {
                        let stone = board.getStone(nx, ny)
                        if (stone != Stone.Empty) {
                            let distance = maxInt64(absInt64(dx), absInt64(dy))
                            let weight = 4 - distance
                            if (stone == selfStone) {
                                score += weight * 3
                            } else {
                                score += weight * 2
                            }
                        }
                    }
                }
                dx += 1
            }
            dy += 1
        }
        return score
    }

    private static func centerBonus(x: Int64, y: Int64): Int64 {
        return 30 - absInt64(x - BOARD_CENTER) - absInt64(y - BOARD_CENTER)
    }

    private static func findFirstEmpty(board: Board): ?Point {
        var y = 0
        while (y < BOARD_SIZE) {
            var x = 0
            while (x < BOARD_SIZE) {
                if (board.isEmptyAt(x, y)) {
                    return Some(Point(x, y))
                }
                x += 1
            }
            y += 1
        }
        return None
    }

    private static func absInt64(value: Int64): Int64 {
        if (value >= 0) {
            return value
        }
        return -value
    }

    private static func maxInt64(left: Int64, right: Int64): Int64 {
        if (left > right) {
            return left
        }
        return right
    }
}
