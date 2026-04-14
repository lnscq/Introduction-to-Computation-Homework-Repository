package finalwork

import std.unittest.*

func seedStone(session: GameSession, x: Int64, y: Int64, stone: Stone): Unit {
    session.board.setStone(x, y, stone)
    session.history.add(Move(x, y, stone, session.history.size + 1))
}

@Test
func testEvaluatePointPrefersImmediateWin() {
    let session = GameSession()
    seedStone(session, 3, 7, Stone.Black)
    seedStone(session, 4, 7, Stone.Black)
    seedStone(session, 5, 7, Stone.Black)
    seedStone(session, 6, 7, Stone.Black)
    seedStone(session, 10, 10, Stone.Black)
    seedStone(session, 11, 10, Stone.Black)

    let winningScore = AiEngine.evaluatePoint(session.board, 7, 7, Stone.Black, Stone.White)
    let openThreeScore = AiEngine.evaluatePoint(session.board, 12, 10, Stone.Black, Stone.White)

    @Assert(winningScore > openThreeScore)
}

@Test
func testEasyDifficultyChoosesImmediateWinningMove() {
    let session = GameSession()
    seedStone(session, 3, 7, Stone.Black)
    seedStone(session, 4, 7, Stone.Black)
    seedStone(session, 5, 7, Stone.Black)
    seedStone(session, 6, 7, Stone.Black)
    seedStone(session, 7, 6, Stone.White)
    seedStone(session, 8, 6, Stone.White)

    let chosen = AiEngine.chooseBestMoveByDifficulty(session, Stone.Black, AiDifficulty.Easy)
    @Assert(chosen.isSome())

    match (chosen) {
        case Some(point) =>
            @Expect(point.x, 7)
            @Expect(point.y, 7)
        case None =>
            @Assert(false)
    }
}

@Test
func testNormalDifficultyBlocksOpponentWinningMove() {
    let session = GameSession()
    seedStone(session, 3, 7, Stone.White)
    seedStone(session, 4, 7, Stone.White)
    seedStone(session, 5, 7, Stone.White)
    seedStone(session, 6, 7, Stone.White)
    seedStone(session, 8, 8, Stone.Black)
    seedStone(session, 9, 8, Stone.Black)
    seedStone(session, 10, 8, Stone.Black)

    let chosen = AiEngine.chooseBestMoveByDifficulty(session, Stone.Black, AiDifficulty.Normal)
    @Assert(chosen.isSome())

    match (chosen) {
        case Some(point) =>
            @Expect(point.x, 7)
            @Expect(point.y, 7)
        case None =>
            @Assert(false)
    }
}
