//
//  GameModels.swift
//  Beckers
//
//  Created by David Cairns on 6/14/22.
//

import Combine
import Foundation

enum PieceColor {
    case red
    case black
}

extension PieceColor {
    mutating func toggle() {
        switch self {
        case .red:
            self = .black
        case .black:
            self = .red
        }
    }
    var opposing: PieceColor {
        switch self {
        case .red:
            return .black
        case .black:
            return .red
        }
    }
}

struct Position: Equatable {
    var row: Int
    var col: Int
}

struct Piece {
    var color: PieceColor
    var position: Position
}

struct Player {
    var pieces: [Piece]
}

struct PlayerMove {
    var fromPosition: Position
    var toPosition: Position
}

struct GameState {
    var players: [PieceColor: Player]
    var currentPlayer: PieceColor = .black
    var winner: PieceColor?
}

extension GameState {
    var blackPlayer: Player { players[.black]! }
    var redPlayer: Player { players[.red]! }
    var allPieces: [Piece] { blackPlayer.pieces + redPlayer.pieces }
}

struct GameViewState {
    struct GamePiece: Identifiable, Hashable {
        var id = UUID()
        var color: PieceColor
    }
    var pieces: [[GamePiece?]]
    var winner: PieceColor?
}

extension GameState {
    var viewState: GameViewState {
        var pieces = [[GameViewState.GamePiece?]](
            repeating: [GameViewState.GamePiece?](
                repeating: nil,
                count: 8
            ),
            count: 8
        )
        for piece in players.values.flatMap(\.pieces) {
            pieces[piece.position.row][piece.position.col] = .init(color: piece.color)
        }
        return .init(
            pieces: pieces,
            winner: winner
        )
    }
}

struct GameEnvironment {
    var redMove: (GameState, GameRunner) async -> PlayerMove
    var blackMove: (GameState, GameRunner) async -> PlayerMove
}

@MainActor
final class GameRunner: ObservableObject {
    var gameState: GameState {
        didSet { self.gameViewState = gameState.viewState }
    }
    @Published var gameViewState: GameViewState
    var environment: GameEnvironment

    private let tappedPositionPublisher = PassthroughSubject<Position, Never>()

    init(
        gameState: GameState,
        environment: GameEnvironment
    ) {
        self.gameState = gameState
        self.gameViewState = gameState.viewState
        self.environment = environment
    }

    func play() {
        Task {
            while gameState.winner == nil {
                let move = await nextMove()

                gameState.apply(move: move, playerColor: gameState.currentPlayer)

                if gameState.blackPlayer.pieces.isEmpty {
                    gameState.winner = .red
                } else if gameState.redPlayer.pieces.isEmpty {
                    gameState.winner = .black
                }

                gameState.currentPlayer.toggle()
            }
        }
    }

    func nextMove() async -> PlayerMove {
        switch gameState.currentPlayer {
        case .black: return await environment.blackMove(gameState, self)
        case .red: return await environment.redMove(gameState, self)
        }
    }

    func didTap(position: Position) { tappedPositionPublisher.send(position) }

    var cancellables = Set<AnyCancellable>()
    func nextTappedPosition() async -> Position {
        return await withCheckedContinuation { continuation in
            self.tappedPositionPublisher
                .first()
                .sink(receiveValue: continuation.resume(returning:))
                .store(in: &self.cancellables)
        }
    }
}

extension GameState {
    init() {
        players = [
            .red: Player(
                pieces: [
                    .init(color: .red, position: .init(row: 0, col: 0)),
                    .init(color: .red, position: .init(row: 0, col: 2)),
                    .init(color: .red, position: .init(row: 0, col: 4)),
                    .init(color: .red, position: .init(row: 0, col: 6)),
                    .init(color: .red, position: .init(row: 1, col: 1)),
                    .init(color: .red, position: .init(row: 1, col: 3)),
                    .init(color: .red, position: .init(row: 1, col: 5)),
                    .init(color: .red, position: .init(row: 1, col: 7)),
                ]
            ),
            .black: Player(
                pieces: [
                    .init(color: .black, position: .init(row: 6, col: 0)),
                    .init(color: .black, position: .init(row: 6, col: 2)),
                    .init(color: .black, position: .init(row: 6, col: 4)),
                    .init(color: .black, position: .init(row: 6, col: 6)),
                    .init(color: .black, position: .init(row: 7, col: 1)),
                    .init(color: .black, position: .init(row: 7, col: 3)),
                    .init(color: .black, position: .init(row: 7, col: 5)),
                    .init(color: .black, position: .init(row: 7, col: 7)),
                ]
            )
        ]
    }

    mutating func apply(move: PlayerMove, playerColor: PieceColor) {
        print("Player \(playerColor) made move \(move)")

        guard
            let pieceIdx = players[playerColor]?.pieces.firstIndex(where: { $0.position == move.fromPosition })
        else {
            print("Improper move:", move)
            return
        }
        players[playerColor]!.pieces[pieceIdx].position = move.toPosition

        // Check for jumped piece.
        let rowJump = move.toPosition.row - move.fromPosition.row
        let colJump = move.toPosition.col - move.fromPosition.col
        if abs(rowJump) == 2 && abs(colJump) == 2 {
            let jumpedPosition = Position(
                row: move.fromPosition.row + rowJump / 2,
                col: move.fromPosition.col + colJump / 2
            )
            guard
                let jumpedPieceIdx = players[playerColor.opposing]!.pieces
                    .firstIndex(where: { $0.position == jumpedPosition })
            else {
                fatalError("Player jumped invalid piece??")
            }
            players[playerColor.opposing]!.pieces.remove(at: jumpedPieceIdx)
        }
    }
}

extension GameEnvironment {
    static var mock: GameEnvironment {
        let ai: (GameState, GameRunner) async -> PlayerMove = { gameState, _ in
            do {
                try await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            } catch {
                print("!!! failed to sleep, because \(error)")
            }

            let piece = gameState.players[gameState.currentPlayer]!.pieces.randomElement()!
            return .init(fromPosition: piece.position, toPosition: .init(row: 0, col: 0))
        }

        return .init(
            redMove: ai,
            blackMove: ai
        )
    }
}

extension GameEnvironment {
    static var humanVsHuman: GameEnvironment {
        let human: (GameState, GameRunner) async -> PlayerMove = { gameState, runner in
            // TODO: nextTappedPosition should be async sequence???
            // Wait for user(s) to tap an piece of the correct player.
            let fromPosition = await nextValue(
                { await runner.nextTappedPosition() },
                passing: { tappedPosition in
                    return gameState.players[gameState.currentPlayer]?.pieces
                        .contains(where: { $0.position == tappedPosition })
                        ?? false
                }
            )
            let toPosition = await nextValue(
                { await runner.nextTappedPosition() },
                passing: { tappedPosition in
                    // No one has a piece there.
                    return !gameState.allPieces
                        .contains(where: { $0.position == tappedPosition })
                    // TODO: Can only move one space UNLESS jumping opposing player's piece.
                }
            )
            return .init(
                fromPosition: fromPosition,
                toPosition: toPosition
            )
        }

        return .init(
            redMove: human,
            blackMove: human
        )
    }
}

func nextValue<T>(_ fetch: () async -> T, passing predicate: (T) -> Bool) async -> T {
    while true {
        let value = await fetch()
        if predicate(value) { return value }
    }
}
