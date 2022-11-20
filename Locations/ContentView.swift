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
    @State var locationServicesEnabled = false
    @State var isUpdatingLocation = false
    @AppStorage("LocationDurationRequest") var duration = LocationPermissionRequest.Duration.whenInUse
    @AppStorage("LocationPrecisionRequest") var precision = LocationPermissionRequest.Precision.imprecise

    var body: some View {
        NavigationView {
            Form {
                Section {
                    LabeledContent("Location Services") {
                        Text(locationServicesEnabled ? "Enabled" : "Disabled")
                            .foregroundStyle(locationServicesEnabled ? Color.green : Color.red)
                    }

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
                            print("done requesting whenInUse: \(permission.name)")
                        }
                    }

                    Button("Request Always Authorization") {
                        Task {
                            let permission = await locationManager.requestPermission(with: .always)
                            print("done requesting always: \(permission.name)")
                        }
                    }

                    Button("Request Temporary Full Accuracy") {
                        Task {
                            let accuracy = await locationManager.requestTemporaryFullAccuracyAuthorization(purposeKey: "PurposeKey")
                            print("done requesting temporary full accuracy: \(accuracy?.name ?? "undefined")")
                        }
                    }

                    Button(isUpdatingLocation ? "Stop Updating Location" : "Start Updating Location") {
                        isUpdatingLocation.toggle()
                    }
                }

                Section("Generalized Permission Requests") {
                    Picker("Duration", selection: $duration) {
                        ForEach(LocationPermissionRequest.Duration.allCases, id: \.self) { value in
                            Text(value.rawValue)
                                .tag(value)
                        }
                    }

                    Picker("Precision", selection: $precision) {
                        ForEach(LocationPermissionRequest.Precision.allCases, id: \.self) { value in
                            Text(value.rawValue)
                                .tag(value)
                        }
                    }

                    Button("Request permission") {
                        Task {
                            let permissionRequest = LocationPermissionRequest(duration: duration, precision: precision)
                            print("Requesting generalized permissions: \(permissionRequest)")
                            let permissionResult = await requestGeneralizedLocationPermissions(permissionRequest)
                            print("Done requesting generalized permissions: \(permissionResult)")
                        }
                    }
                }

                Section {
                    Button("Location Settings") {
                        let url = URL(string: "\(UIApplication.openSettingsURLString)&path=LOCATION_SERVICES")!
                        UIApplication.shared.open(url)
                    }
                }
            }
            .navigationBarTitle("Locations")
        }
        .onAppear {
            locationAuthorization = locationManager.getAuthorizationStatus()
            accuracyAuthorization = locationManager.getAccuracyAuthorization()

            Task.detached {
                let enabled = CLLocationManager.locationServicesEnabled()
                await MainActor.run {
                    locationServicesEnabled = enabled
                }
            }
        }
        .task {
            for await event in await locationManager.startMonitoringLocationEnabled() {
                switch event {
                case .didUpdate(let enabled):
                    locationServicesEnabled = enabled
                }
            }
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

    // The generalized location permission flow goes like this:
    func requestGeneralizedLocationPermissions(_ permissionRequest: LocationPermissionRequest) async -> LocationPermissionResult {
        let durationResult = await requestGeneralizedLocationDurationPermissions(permissionRequest.duration)
        let precisionResult = await requestGeneralizedLocationPrecisionPermissions(permissionRequest.precision)
        return LocationPermissionResult(duration: durationResult, precision: precisionResult)
    }

    private func requestGeneralizedLocationDurationPermissions(
        _ durationRequest: LocationPermissionRequest.Duration
    ) async -> LocationPermissionResult.Duration {
        var permission: CLAuthorizationStatus
        switch durationRequest {
        case .whenInUse:
            permission = await requestWhenInUsePermission()
        case .always:
            permission = await requestWhenInUsePermission()
            if permission == .authorizedWhenInUse {
                permission = await requestAlwaysPermission()
            }
        }
        return permission.permissionResult
    }

    private func requestGeneralizedLocationPrecisionPermissions(
        _ precisionRequest: LocationPermissionRequest.Precision
    ) async -> LocationPermissionResult.Precision {
        var accuracy: CLAccuracyAuthorization?
        switch precisionRequest {
        case .precise:
            accuracy = await requestTemporaryFullAccuracy()
        case .imprecise:
            accuracy = locationManager.getAccuracyAuthorization()
        }
        return accuracy?.permissionResult ?? .denied
    }

    private func requestTemporaryFullAccuracy() async -> CLAccuracyAuthorization? {
        print("requesting TemporaryFullAccuracy")
        let accuracy = await locationManager.requestTemporaryFullAccuracyAuthorization(purposeKey: "PurposeKey")
        print("done requesting TemporaryFullAccuracy: \(accuracy?.name ?? "undefined")")
        return accuracy
    }

    private func requestAlwaysPermission() async -> CLAuthorizationStatus {
        print("requesting Always permission")
        let permission = await locationManager.requestPermission(with: .always)
        print("done requesting Always permission: \(permission.name)")
        return permission
    }

    private func requestWhenInUsePermission() async -> CLAuthorizationStatus {
        print("requesting WhenInUse permission")
        let permission = await locationManager.requestPermission(with: .whenInUsage)
        print("done requesting WhenInUse permission: \(permission.name)")
        return permission
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

struct LocationPermissionRequest {
    let duration: Duration
    let precision: Precision

    public init(duration: Duration, precision: Precision) {
        self.precision = precision
        self.duration = duration
    }

    enum Precision: String, Identifiable, CaseIterable {
        case precise
        case imprecise
        var id: String { rawValue }
    }

    enum Duration: String, Identifiable, CaseIterable {
        case whenInUse
        case always
        var id: String { rawValue }
    }
}

struct LocationPermissionResult {
    let duration: Duration
    let precision: Precision

    public init(duration: Duration, precision: Precision) {
        self.precision = precision
        self.duration = duration
    }

    enum Precision {
        case notDetermined
        case precise
        case imprecise
        case denied
    }

    enum Duration {
        case notDetermined
        case whenInUse
        case always
        case denied
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
    var permissionResult: LocationPermissionResult.Duration {
        switch self {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .denied
        case .denied:
            return .denied
        case .authorizedAlways:
            return .always
        case .authorizedWhenInUse:
            return .whenInUse
        @unknown default:
            return .denied
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
    var permissionResult: LocationPermissionResult.Precision {
        switch self {
        case .fullAccuracy:
            return .precise
        case .reducedAccuracy:
            return .imprecise
        @unknown default:
            return .denied
        }
    }
}
