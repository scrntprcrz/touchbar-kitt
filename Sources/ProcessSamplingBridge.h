#ifndef KITT_PROCESS_SAMPLING_BRIDGE_H
#define KITT_PROCESS_SAMPLING_BRIDGE_H

#include <stdint.h>

typedef struct {
    int32_t pid;
    int32_t parentPID;
    uint64_t birthSeconds;
    uint64_t birthMicroseconds;
} KITTProcessIdentity;

typedef struct {
    uint64_t cpuNanoseconds;
    uint64_t residentBytes;
    uint64_t threadCount;
    uint64_t contextSwitches;
    uint64_t diskReadBytes;
    uint64_t diskWriteBytes;
    int32_t diskReadable;
    uint64_t energyNanojoules;
    int32_t energyReadable;
} KITTProcessCounters;

typedef struct {
    int32_t pid;
    uint64_t gpuNanoseconds;
} KITTGPUCounter;

int32_t KITTReadProcessPath(int32_t pid, char *buffer, int32_t capacity);
int32_t KITTListGPUCounters(KITTGPUCounter *buffer, int32_t capacity);

int32_t KITTListProcessIDs(int32_t *buffer, int32_t capacity);
int32_t KITTReadProcessIdentity(int32_t pid, KITTProcessIdentity *result);
int32_t KITTReadProcessCounters(int32_t pid, KITTProcessCounters *result);

#endif
