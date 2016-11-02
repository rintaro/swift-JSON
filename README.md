<p align="center">
<img src="https://cdn.rawgit.com/rintaro/swift-JSON/master/Images/logo.svg" alt="swift-JSON">
</p>

<p align="center">
<a href="https://swift.org/"><img src="https://img.shields.io/badge/Swift-3.0.1-blue.svg" alt="Swift: 3.0.1"></a>
<img src="https://img.shields.io/badge/platforms-macOS | iOS | tvOS | Linux-lightgrey.svg" alt="platforms: macOS, iOS, tvOS, Linux">
<a href="https://github.com/Carthage/Carthage"><img src="https://img.shields.io/badge/Carthage-compatible-4BC51D.svg" alt="Carthage: compatible"></a>
<a href="https://github.com/apple/swift-package-manager"><img src="https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg" alt="SwiftPM: compatible"></a>
</p>

# JSON

Yet another Swift JSON encoder/decoder.
Intended to be fast and [RFC7159](https://tools.ietf.org/html/rfc7159) compliant.

## Getting Started

#### Swift Package Manager

```swift
import PackageDescription

let package = Package(
    name: "hello",
    dependencies: [
        .Package(url: "https://github.com/rintaro/Swift-JSON.git", majorVersion: 0, minor: 2),
    ]
)
```

#### Carthage

```
github "rintaro/swift-JSON" ~> 0.2
```

## Using JSON

#### decode 

(a.k.a. parse or deserialize)

```swift
import JSON

let jsonData: Data = ...

do {

    let value = try JSON.decode(jsonData)
    // do something...

} catch let e as JSONParsingError {
    print(e)
}

```

#### encode 

(a.k.a. dump or serialize)

```swift
import JSON

let value: Any = ...

do {

    let data = try JSON.encode(value)
    // do something...

} catch let e as JSONPrintingError {
    print(e)
}

```

## Requirements

* Swift 3.0.1 (Xcode8.1 on macOS)
* Foundation
