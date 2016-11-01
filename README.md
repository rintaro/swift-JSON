# JSON

Yet another JSON encoder/decoder.

## Getting Started

#### Swift Package Manager

```swift
import PackageDescription

let package = Package(
    name: "hello",
    dependencies: [
        .Package(url: "https://github.com/rintaro/Swift-JSON.git", majorVersion: 0, minor: 1),
    ]
)
```

#### Carthage

Cartfile

```
github "rintaro/swift-JSON" ~> 0.1
```

## Using JSON

Via static methods.

```swift
import JSON

func foo(data: Data) throws -> Data? {
    let objAny = try JSON.decode(jsonData)
    return try JSON.encode(objAny)
}
```

Via instance methods.

```swift
import JSON

func foo(data: Data) throws -> Data? {
    let json = JSON()

    let objAny = json.decode(jsonData)
    return try json.encode(objAny)
}
```

## Requirements

* Swift 3.0.1
* Foundation
