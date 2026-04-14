package finalwork

import std.unittest.*

func mustPlace(session: GameSession, x: Int64, y: Int64): Unit {
    let result = GameRules.placeStone(session, x, y)
    @Assert(result.success)
}

@Test
func testValidFirstMove() {
    let session = GameSession()
    let result = GameRules.placeStone(session, 7, 7)

    @Expect(result.success)
    @Expect(session.board.getStone(7, 7), Stone.Black)
    @Expect(session.currentPlayer, Stone.White)
    @Expect(session.history.size, 1)
    @Expect(session.result, GameResult.Playing)
    @Expect(session.finished, false)
}

@Test
func testRejectInvalidCoordinate() {
    let session = GameSession()
    let result = GameRules.placeStone(session, -1, 0)

    @Expect(result.success, false)
    @Expect(result.message, "invalid coordinate")
    @Expect(session.history.size, 0)
    @Expect(session.result, GameResult.Playing)
}

@Test
func testRejectOccupiedPosition() {
    let session = GameSession()
    mustPlace(session, 3, 3)

    let result = GameRules.placeStone(session, 3, 3)

    @Expect(result.success, false)
    @Expect(result.message, "position already occupied")
    @Expect(session.history.size, 1)
    @Expect(session.currentPlayer, Stone.White)
}

@Test
func testDetectHorizontalWin() {
    let session = GameSession()

    mustPlace(session, 0, 0)
    mustPlace(session, 0, 1)
    mustPlace(session, 1, 0)
    mustPlace(session, 1, 1)
    mustPlace(session, 2, 0)
    mustPlace(session, 2, 1)
    mustPlace(session, 3, 0)
    mustPlace(session, 3, 1)

    let finalMove = GameRules.placeStone(session, 4, 0)

    @Expect(finalMove.success)
    @Expect(session.result, GameResult.BlackWin)
    @Expect(session.finished)
    @Expect(session.currentPlayer, Stone.Black)
    @Expect(session.history.size, 9)
}

@Test
func testCannotPlaceAfterGameFinished() {
    let session = GameSession()

    mustPlace(session, 0, 0)
    mustPlace(session, 0, 1)
    mustPlace(session, 1, 0)
    mustPlace(session, 1, 1)
    mustPlace(session, 2, 0)
    mustPlace(session, 2, 1)
    mustPlace(session, 3, 0)
    mustPlace(session, 3, 1)
    mustPlace(session, 4, 0)

    let result = GameRules.placeStone(session, 4, 4)

    @Expect(result.success, false)
    @Expect(result.message, "game already finished")
    @Expect(session.history.size, 9)
    @Expect(session.board.getStone(4, 4), Stone.Empty)
}
