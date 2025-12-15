#pragma once
#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
// winsock2.h must be included before windows.h
#define byte win_byte
#include <winsock2.h>
#include <windows.h>
#undef byte
#include <direct.h>
#include <io.h>
#include <sys/stat.h>
#include <string>
#include <vector>
#include <stdlib.h>

struct dirent {
    char d_name[MAX_PATH];
    unsigned char d_type;
};

#define DT_DIR 4
#define DT_REG 8

struct DIR {
    HANDLE hFind;
    WIN32_FIND_DATAA data;
    dirent entry;
    bool first;
};

inline DIR* opendir(const char* name) {
    std::string pattern = std::string(name) + "\\*";
    DIR* dir = new DIR;
    dir->hFind = FindFirstFileA(pattern.c_str(), &dir->data);
    if (dir->hFind == INVALID_HANDLE_VALUE) {
        delete dir;
        return nullptr;
    }
    dir->first = true;
    return dir;
}

inline struct dirent* readdir(DIR* dir) {
    if (!dir->first) {
        if (!FindNextFileA(dir->hFind, &dir->data)) {
            return nullptr;
        }
    }
    dir->first = false;
    strncpy_s(dir->entry.d_name, dir->data.cFileName, MAX_PATH);
    if (dir->data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) {
        dir->entry.d_type = DT_DIR;
    } else {
        dir->entry.d_type = DT_REG;
    }
    return &dir->entry;
}

inline int closedir(DIR* dir) {
    FindClose(dir->hFind);
    delete dir;
    return 0;
}

// POSIX Compatibility Shims
#define mkdir(path, mode) _mkdir(path)
#define rmdir _rmdir
#define access _access
#define F_OK 0

#ifndef S_ISDIR
#define S_ISDIR(mode) (((mode) & S_IFMT) == S_IFDIR)
#endif

#define S_IRWXU 0700
#define S_IRWXG 0070
#define S_IROTH 0004
#define S_IXOTH 0001

inline char* realpath(const char* path, char* resolved_path) {
    return _fullpath(resolved_path, path, MAX_PATH);
}

#define popen _popen
#define pclose _pclose

// kill shim
#define SIGKILL 9
inline int kill(int pid, int sig) {
    if (sig == 0) {
        HANDLE h = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, pid);
        if (h) {
            CloseHandle(h);
            return 0;
        }
        return -1;
    }
     // TerminateProcess if strictly needed, but for now just validation
    return -1;
}

// select on Windows only works for sockets.
// For files, we might need a different approach or just stub it if not critical.
// common.cc uses it for timeout. For now, let's keep it as is and see if winsock2 includes generic select that compiles (but might fail at runtime/link).
// Winsock select expects fd_set pointers. generic standard select also does.
// But CRT file descriptors (int) are not SOCKETs.
// We will need to modify common.cc to guard the select usage if logic permits.

#endif
