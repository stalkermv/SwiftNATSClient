//
//  NATSClient+StateHolder.swift
//  SwiftNATSClient
//
//  Created by Valeriy Malishevskyi on 27.06.2025.
//

extension NATSClient {
    actor StateHolder {
        private var state: State = .idle
        
        func getState() -> State { state }
        func setState(_ newState: State) { state = newState }
    }
}
