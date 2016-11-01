/// In optimized configuration, statically convert an ASCII character literal to
/// UTF16 CodeUnit (UInt16)
func ascii16(_ x: UnicodeScalar) -> UTF16.CodeUnit {
    return UTF16.CodeUnit(truncatingBitPattern: x.value)
}

/// In optimized configuration, statically convert an ASCII character literal to
/// UTF8 CodeUnit (UInt8)
func ascii8(_ x: UnicodeScalar) -> UTF8.CodeUnit {
    return UTF8.CodeUnit(truncatingBitPattern: x.value)
}
