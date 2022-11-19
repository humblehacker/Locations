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
    @State var currentLocation: CLLocationCoordinate2D = kCLLocationCoordinate2DInvalid
    @State var isUpdatingLocation = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    LabeledContent("Location Authorization") {
                        Text(locationAuthorization.name).foregroundStyle(locationAuthorization.color)
                    }

                    LabeledContent("Accuracy Authorization") {
                        Text(accuracyAuthorization.name)
                            .foregroundStyle(accuracyAuthorization.color)
                            .grayscale(locationAuthorization == .notDetermined ? 1 : 0)
                    }

                    HStack {
                        HStack {
                            LabeledContent("Latitude", value: currentLocation.latitude, format: .number.precision(.fractionLength(1...8)))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)

                        Divider()

                        HStack {
                            LabeledContent("Longitude", value: currentLocation.longitude, format: .number.precision(.fractionLength(1...8)))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .labeledContentStyle(CustomLabeledContentStyle())

                Section {
                    Button("Request When In Use Authorization") {
                        Task {
                            let permission = await locationManager.requestPermission(with: .whenInUsage)
                            print("done requesting whenInUse: \(permission)")
                        }
                    }

                    Button("Request Always Authorization") {
                        Task {
                            let permission = await locationManager.requestPermission(with: .always)
                            print("done requesting always: \(permission)")
                        }
                    }

                    Button("Request Temporary Full Accuracy") {
                        Task {
                            let accuracy = await locationManager.requestTemporaryFullAccuracyAuthorization(purposeKey: "PurposeKey")
                            print("done requesting temporary full accuracy: \(accuracy)")
                        }
                    }

                    Button(isUpdatingLocation ? "Stop Updating Location" : "Start Updating Location") {
                        isUpdatingLocation.toggle()
                    }
                }

                Section {
                    Button("Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            }
                .navigationBarTitle("Locations")
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
        .onChange(of: isUpdatingLocation) { isUpdating in
            Task {
                if isUpdating {
                    for await event in await locationManager.startUpdatingLocation() {
                        switch event {
                        case .didPaused:
                            print("location paused")
                        case .didResume:
                            print("location resumed")
                        case .didUpdateLocations(locations: let locations):
                            print("location updated \(locations)")
                            currentLocation = locations.last?.coordinate ?? kCLLocationCoordinate2DInvalid
                        case .didFailWith(error: let error):
                            print("location failed: \(error.localizedDescription)")
                        }
                    }
                } else {
                    locationManager.stopUpdatingLocation()
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

struct CustomLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading) {
            configuration.label.font(.caption).foregroundStyle(.gray)
            configuration.content
        }
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
    var color: Color {
        switch self {
        case .notDetermined: return Color.orange
        case .restricted: return Color.red
        case .denied: return Color.red
        case .authorizedAlways: return Color.green
        case .authorizedWhenInUse: return Color.green
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
    var color: Color {
        switch self {
        case .fullAccuracy: return Color.green
        case .reducedAccuracy: return Color.orange
        @unknown default: fatalError()
        }
    }
}
