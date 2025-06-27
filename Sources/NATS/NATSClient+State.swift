//
//  NATSClient+State.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

extension NATSClient {
    enum State: Sendable, Equatable {
        case idle
        case connecting
        case connected
        case closing
        case closed
        case failed(Error)
        
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.connecting, .connecting), (.connected, .connected), (.closing, .closing), (.closed, .closed): return true
            case (.failed, .failed): return true // ignore error details for equality
            default: return false
            }
        }
    }
}
