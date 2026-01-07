// Stub implementations for PAYLOAD_* symbols and other missing symbols
// These are normally provided by the Sorbet binary but need stubs for library usage

#include <stddef.h>
#include <string.h>
#include <string>

// Payload stubs - empty payloads for library usage
extern "C" {
const char PAYLOAD_EMPTY[] = "";
const char PAYLOAD_FILE_TABLE[] = "";
const char PAYLOAD_NAME_TABLE[] = "";
const char PAYLOAD_SYMBOL_TABLE[] = "";
}

// // Demangle stub - just return the input string
// // Note: C++ linkage (no extern "C") to match Sorbet's expectation
// const char* demangle(const char* mangled) {
//     return mangled;
// }

// // Exec stub - simple stub that does nothing
// // Note: C++ linkage (no extern "C") to match Sorbet's expectation
// void exec(std::string cmd) {
//     // No-op for library usage
// }
