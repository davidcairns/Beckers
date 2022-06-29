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
                let move: PlayerMove
                switch gameState.currentPlayer {
                case .black: move = await environment.blackMove(gameState, self)
                case .red: move = await environment.redMove(gameState, self)
                }

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

    func didTap(position: Position) {
        tappedPositionPublisher.send(position)
    }

    var cancellables = Set<AnyCancellable>()
    func nextTappedPosition() async -> Position {
        print("!!! awaiting next tapped…")
        return await withCheckedContinuation { continuation in
            // FIXME??
            self.tappedPositionPublisher
                .first()
                .handleEvents(
                    receiveOutput: { print("!!! tappedPositionPublisher emitted", $0) },
                    receiveCompletion: { _ in print("!!! tappedPositionPublisher completed") }
                )
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
        let rowJump = move.fromPosition.row - move.toPosition.row
        let colJump = move.fromPosition.col - move.toPosition.col
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
//            let pieceIdx = Int.random(in: gameState.players[gameState.currentPlayer]!.pieces.indices)
            return .init(fromPosition: piece.position, toPosition: .init(row: 0, col: 0))
        }

        return .init(
            redMove: ai,
            blackMove: ai
        )
    }
}

extension GameEnvironment {
    static func env() -> GameEnvironment {
        let human: (GameState, GameRunner) async -> PlayerMove = { _, runner in
            .init(
                fromPosition: await runner.nextTappedPosition(),
                toPosition: await runner.nextTappedPosition()
            )
        }

        let ai: (GameState, GameRunner) async -> PlayerMove = { gameState, _ in
            do {
                try await Task.sleep(nanoseconds: 2 * 1_000_000_000)
            } catch {
                print("!!! failed to sleep, because \(error)")
            }

            let piece = gameState.players[gameState.currentPlayer]!.pieces.randomElement()!
//            let pieceIdx = Int.random(in: gameState.players[gameState.currentPlayer]!.pieces.indices)
            return .init(fromPosition: piece.position, toPosition: .init(row: 0, col: 0))
        }

        return .init(
            redMove: human,
            blackMove: human
        )
    }
}
