#ifdef _WIN32
#include "absl/debugging/symbolize.h"
#include "spdlog/spdlog.h"
#include "common/os/os.h"
#include <string>

using namespace std;

string addr2line(string_view programName, void const *const *addr, int count) {
    return "";
}

string getProgramName() {
    return "sorbet.exe";
}

bool amIBeingDebugged() {
    return false;
}

bool stopInDebugger() {
    return false;
}

bool setCurrentThreadName(string_view name) {
    // Requires Windows 10 SetThreadDescription, ignoring for now or could use RaiseException trick
    return true;
}

bool bindThreadToCore(NativeThreadHandle handle, int coreId) {
    // Not implemented
    return false;
}

void initializeSymbolizer(char *argv0) {
    absl::InitializeSymbolizer(argv0);
}
#endif
