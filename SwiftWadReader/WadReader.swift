//
//  WadReader.swift
//  SwiftWadReader
//
//  Created by Benedikt Terhechte on 15/07/16.
//  Copyright © 2016 Benedikt Terhechte. All rights reserved.
//

import Foundation

// FIXME: Seperate File

extension Data {
    func scanValue<T: SignedInteger>(start: Int, length: Int) -> T {
        return self.subdata(in: start..<start+length).withUnsafeBytes {
            (pointer: UnsafePointer<T>) -> T in
            return pointer.pointee
        }
    }
}

public enum WadReaderError: Error {
    case invalidWadFile(reason: String)
    case invalidLup(reason: String)
}

public struct Lump {
    public let filepos: Int32
    public let size: Int32
    public let name: String
}

public class WadReader {
    
    /// The lumps that were parsed out of the wad file
    private var lumps: [Lump] = []
    
    /// The MMapped contents of the Wad file
    private let data: Data
    
    private var numberOfLumps: Int32 = 0
    
    private var directoryLocation: Int32 = 0
    
    public init(wadFile file: URL) throws {
        data = try Data(contentsOf: file, options: .alwaysMapped)
    }
    
    public func parse() throws -> [Lump] {
        try validateWadFile()
        try parseWadFile()
        return lumps
    }
    
    /**
     Validate the contents of the wad file by inspecting the header.
     See http://doom.wikia.com/wiki/WAD
     and http://doomlegacy.sourceforge.net/hosted/doomspec1666.txt
    */
    public func validateWadFile() throws {
        // Several Wad File definitions
        let wadMaxSize = 12, wadLumpsStart = 4, wadDirectoryStart = 8, wadDefSize = 4
        
        // A WAD file always starts with a 12-byte header.
        guard data.count >= wadMaxSize else { throw WadReaderError.invalidWadFile(reason: "File is too small") }
            
        // It contains three values:
        
        // The ASCII characters "IWAD" or "PWAD". Defines whether the WAD is an IWAD or a PWAD.
        let validStart = "IWAD".data(using: String.Encoding.ascii)!
        guard data.subdata(in: 0..<wadDefSize) == validStart else
        { throw WadReaderError.invalidWadFile(reason: "Not an IWAD") }
        
        // An integer specifying the number of lumps in the WAD.
        let lumpsInteger: Int32 = data.scanValue(start: wadLumpsStart, length: wadDefSize)
        
        // An integer holding a pointer to the location of the directory.
        let directoryInteger: Int32 = data.scanValue(start: wadDirectoryStart, length: wadDefSize)
        
        guard lumpsInteger > 0 && directoryInteger > Int32(wadMaxSize)
            else {
                throw WadReaderError.invalidWadFile(reason: "Empty Wad File")
        }

        directoryLocation = directoryInteger
        numberOfLumps = lumpsInteger
    }
    
    /**
     Parse the list of lumps in the wad file
     */
    public func parseWadFile() throws {
        let wadDirectoryEntrySize = 16
        
        // The directory associates names of lumps with the data that belong to them. It consists of a number of entries, each with a length of 16 bytes. The length of the directory is determined by the number given in the WAD header.
        let directory = data.subdata(in: Int(directoryLocation)..<(Int(directoryLocation) + Int(numberOfLumps) * wadDirectoryEntrySize))
        
        var floorsStarted = false
        
        for currentIndex in stride(from: 0, to: directory.count, by: wadDirectoryEntrySize) {
            
            let currentDirectoryEntry = directory.subdata(in: currentIndex..<currentIndex+wadDirectoryEntrySize)
            
            // An integer holding a pointer to the start of the lump's data in the file.
            let lumpStart: Int32 = currentDirectoryEntry.scanValue(start: 0, length: 4)

            // An integer representing the size of the lump in bytes.
            let lumpSize: Int32 = currentDirectoryEntry.scanValue(start: 4, length: 4)
            
            // An ASCII string defining the lump's name. Only the characters A-Z (uppercase), 0-9, and [ ] - _ should be used in lump names (an exception has to be made for some of the Arch-Vile sprites, which use "\"). When a string is less than 8 bytes long, it should be null-padded to the tight byte.
            
            let nameData = currentDirectoryEntry.subdata(in: 8..<16)
            
            let optionalLumpName = nameData.withUnsafeBytes({ (pointer: UnsafePointer<CChar>) -> String? in
                var localPointer = pointer
                for _ in 0..<8 {
                    guard localPointer.pointee != CChar(0) else { break }
                    localPointer = localPointer.successor()
                }
                let position = pointer.distance(to: localPointer)
                return String(data: nameData.subdata(in: 0..<position),
                              encoding: String.Encoding.ascii)
            })
            guard let lumpName = optionalLumpName else {
                throw WadReaderError.invalidLup(reason: "Could not decode lump name for bytes \(nameData)")
            }
            
            if lumpName == "F_START" {
                floorsStarted = true
                continue
            } else if lumpName == "F_END" {
                floorsStarted = false
            }
            
            if floorsStarted {
                lumps.append(Lump(filepos: lumpStart, size: lumpSize, name: lumpName))
            }
            
        }
        
    }
}
