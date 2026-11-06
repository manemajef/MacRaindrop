//
//  AppCommands.swift
//  MacRaindrop
//
//  Created by Rotem Semah on 05/11/2026.
//

import Foundation
import SwiftUI

struct AppCommands: Commands {
    @AppStorage("showInspector") private var isInspectorPresented = true
    
    var body: some Commands {
        CommandGroup(after: .sidebar) {
            Button(
                isInspectorPresented ? "Hide Inspector" : "Show Inspector"
            ) {
                isInspectorPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: .command)
            
        }
    }
}
