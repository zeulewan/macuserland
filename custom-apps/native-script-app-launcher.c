#include <errno.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char *argv[]) {
    char rawPath[PATH_MAX];
    uint32_t rawPathSize = sizeof(rawPath);

    if (_NSGetExecutablePath(rawPath, &rawPathSize) != 0) {
        fprintf(stderr, "Executable path is too long\n");
        return 126;
    }

    char executablePath[PATH_MAX];
    if (realpath(rawPath, executablePath) == NULL) {
        strncpy(executablePath, rawPath, sizeof(executablePath) - 1);
        executablePath[sizeof(executablePath) - 1] = '\0';
    }

    char *executableName = strrchr(executablePath, '/');
    executableName = executableName ? executableName + 1 : executablePath;

    char *contentsMarker = strstr(executablePath, "/Contents/MacOS/");
    if (contentsMarker == NULL) {
        fprintf(stderr, "Not running from an app bundle: %s\n", executablePath);
        return 126;
    }

    size_t contentsPathLength = (size_t)(contentsMarker - executablePath) + strlen("/Contents");
    char scriptPath[PATH_MAX];
    int written = snprintf(
        scriptPath,
        sizeof(scriptPath),
        "%.*s/Resources/%s.sh",
        (int)contentsPathLength,
        executablePath,
        executableName
    );

    if (written < 0 || (size_t)written >= sizeof(scriptPath)) {
        fprintf(stderr, "Script path is too long\n");
        return 126;
    }

    if (access(scriptPath, R_OK) != 0) {
        fprintf(stderr, "Cannot read script %s: %s\n", scriptPath, strerror(errno));
        return 126;
    }

    if (argc == 2 && strcmp(argv[1], "--native-launcher-self-test") == 0) {
        printf("%s\n", scriptPath);
        return 0;
    }

    char **newArgv = calloc((size_t)argc + 2, sizeof(char *));
    if (newArgv == NULL) {
        perror("calloc");
        return 126;
    }

    newArgv[0] = "/bin/bash";
    newArgv[1] = scriptPath;
    for (int i = 1; i < argc; i++) {
        newArgv[i + 1] = argv[i];
    }

    const char *home = getenv("HOME");
    if (home != NULL) {
        chdir(home);
    }

    execv("/bin/bash", newArgv);
    fprintf(stderr, "Failed to launch /bin/bash: %s\n", strerror(errno));
    free(newArgv);
    return 126;
}
