# JSON

Yet another JSON encoder/decoder.

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
