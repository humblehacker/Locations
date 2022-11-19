//
//  ContentView.swift
//  Locations
//
//  Created by David Whetstone on 11/18/22.
//
//

import AsyncLocationKit
import CoreLocation
import SwiftUI

struct ContentView: View {
    @State var locationManager = AsyncLocationManager()
    @State var locationAuthorization: CLAuthorizationStatus = .notDetermined
    @State var accuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy
    var body: some View {
        Form {
            Section {
                LabeledContent(
                    content: { Text(locationAuthorization.name) },
                    label: { Text("Location Authorization") }
                )

                LabeledContent(
                    content: { Text(accuracyAuthorization.name) },
                    label: { Text("Accuracy Authorization") }
                )

                Button("Request When In Use Authorization") {
                    Task {
                        await locationManager.requestPermission(with: .whenInUsage)
                        print("done requesting whenInUse")
                    }
                }

                Button("Request Always Authorization") {
                    Task {
                        await locationManager.requestPermission(with: .always)
                        print("done requesting always")
                    }
                }

                Button("Request Temporary Full Accuracy") {
                    Task {
                        await locationManager.requestTemporaryFullAccuracyAuthorization(purposeKey: "PurposeKey")
                        print("done requesting temporary")
                    }
                }

                Button("Settings") {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                }
            }
        }
        .onAppear {
            locationAuthorization = locationManager.getAuthorizationStatus()
            accuracyAuthorization = locationManager.getAccuracyAuthorization()
        }
        .task {
            for await event in await locationManager.startMonitoringAuthorization() {
                switch event {
                case .didUpdate(let status):
                    locationAuthorization = status
                }
            }
        }
        .task {
            for await event in await locationManager.startMonitoringAccuracyAuthorization() {
                switch event {
                case .didUpdate(let authorization):
                    accuracyAuthorization = authorization
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

extension CLAuthorizationStatus {
    var name: String {
        switch self {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorizedAlways: return "Authorized Always"
        case .authorizedWhenInUse: return "Authorized When in Use"
        @unknown default: fatalError()
        }
    }
}

extension CLAccuracyAuthorization {
    var name: String {
        switch self {
        case .fullAccuracy: return "Full Accuracy"
        case .reducedAccuracy: return "Reduced Accuracy"
        @unknown default: fatalError()
        }
    }
}
