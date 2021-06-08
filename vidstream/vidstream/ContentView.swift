//
//  ContentView.swift
//  vidtest
//
//  Created by User on 10/19/20.
//

import SwiftUI

struct ContentView: View {
    @available(iOS 13.0.0, *)
    var body: some View {
        if #available(iOS 14.0, *) {
            if #available(iOS 13.0, *) {
                
            } else {
                // Fallback on earlier versions
            }
        } else {
            // Fallback on earlier versions
        }
        Text("Hello, world!")
            .padding()
    }
}

struct ContentView_Previews: PreviewProvider {
    @available(iOS 13.0.0, *)
    static var previews: some View {
        ContentView()
    }
}
