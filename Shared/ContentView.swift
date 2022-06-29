//
//  ContentView.swift
//  Shared
//
//  Created by David Cairns on 6/8/22.
//

import Combine
import SwiftUI

struct ContentView: View {
    @ObservedObject var gameRunner = GameRunner(
        gameState: GameState(),
        environment: .env()
    )

//    private let tappedPositionPublisher = PassthroughSubject<Position, Never>()
//
//    func nextTappedPosition() async -> Position {
//        return await withUnsafeContinuation { continuation in
//            // FIXME??
//            _ = self.tappedPositionPublisher
//                .sink(receiveValue: continuation.resume(returning:))
//        }
//    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(gameRunner.gameViewState.pieces.indices, id: \.self) { rowIdx in
                HStack(spacing: 0) {
                    ForEach(gameRunner.gameViewState.pieces[rowIdx].indices, id: \.self) { colIdx in
                        ZStack {
                            // Board space:
                            Rectangle()
                                .fill(
                                    (rowIdx + colIdx).isMultiple(of: 2)
                                        ? Color.black
                                        : Color.red
                                )
                                .gesture(
                                    TapGesture()
                                        .onEnded { _ in
                                            print("!!! tapped", rowIdx, colIdx)
//                                            tappedPositionPublisher.send(.init(row: rowIdx, col: colIdx))
                                            gameRunner.didTap(position: .init(row: rowIdx, col: colIdx))
                                        }
                                )

                            // Piece:
                            switch gameRunner.gameViewState.pieces[rowIdx][colIdx]?.color {
                            case nil:
                                EmptyView()
                            case .black:
                                GamePieceView(color: .black)
                                    .allowsHitTesting(false)
                            case .red:
                                GamePieceView(color: .red)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { gameRunner.play() }
    }
}

struct GamePieceView: View {
    var color: Color

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 2)
                .fill(.yellow)
            Circle()
                .inset(by: 4)
                .fill(color)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
