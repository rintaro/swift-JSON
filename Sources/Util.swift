//
//  Util.swift
//  JSON
//
//  Created by rintaro on 10/31/16.
//
//

func ascii16(_ x: UnicodeScalar) -> UTF16.CodeUnit {
    return UTF16.CodeUnit(truncatingBitPattern: x.value)
}

func ascii8(_ x: UnicodeScalar) -> UTF8.CodeUnit {
    return UTF8.CodeUnit(truncatingBitPattern: x.value)
}
