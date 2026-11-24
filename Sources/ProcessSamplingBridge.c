#include "ProcessSamplingBridge.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <string.h>
#include <mach/mach_time.h>
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>

int32_t KITTListProcessIDs(int32_t *buffer, int32_t capacity) {
    if (buffer == NULL || capacity <= 0) return 0;
    return proc_listallpids(buffer, capacity * (int32_t)sizeof(int32_t));
}

int32_t KITTReadProcessIdentity(int32_t pid, KITTProcessIdentity *result) {
    if (pid <= 0 || result == NULL) return 0;
    struct proc_bsdinfo info;
    memset(&info, 0, sizeof(info));
    int read = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
    if (read != sizeof(info)) return 0;
    result->pid = pid;
    result->parentPID = (int32_t)info.pbi_ppid;
    result->birthSeconds = info.pbi_start_tvsec;
    result->birthMicroseconds = info.pbi_start_tvusec;
    return 1;
}

int32_t KITTReadProcessCounters(int32_t pid, KITTProcessCounters *result) {
    if (pid <= 0 || result == NULL) return 0;
    struct proc_taskinfo task;
    memset(&task, 0, sizeof(task));
    int read = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task));
    if (read != sizeof(task)) return 0;
    memset(result, 0, sizeof(*result));
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    uint64_t ticks = task.pti_total_user + task.pti_total_system;
    if (timebase.denom > 0) {
        result->cpuNanoseconds = (uint64_t)(((__uint128_t)ticks * timebase.numer) / timebase.denom);
    }
    result->residentBytes = task.pti_resident_size;
    result->threadCount = (uint64_t)task.pti_threadnum;
    result->contextSwitches = (uint64_t)task.pti_csw;
    struct rusage_info_v6 extended;
    memset(&extended, 0, sizeof(extended));
    if (proc_pid_rusage(pid, RUSAGE_INFO_V6, (rusage_info_t *)&extended) == 0) {
        result->diskReadBytes = extended.ri_diskio_bytesread;
        result->diskWriteBytes = extended.ri_diskio_byteswritten;
        result->diskReadable = 1;
        result->energyNanojoules = extended.ri_energy_nj;
        result->energyReadable = 1;
    } else {
        struct rusage_info_v2 basic;
        memset(&basic, 0, sizeof(basic));
        if (proc_pid_rusage(pid, RUSAGE_INFO_V2, (rusage_info_t *)&basic) == 0) {
            result->diskReadBytes = basic.ri_diskio_bytesread;
            result->diskWriteBytes = basic.ri_diskio_byteswritten;
            result->diskReadable = 1;
        }
    }
    return 1;
}

int32_t KITTReadProcessPath(int32_t pid, char *buffer, int32_t capacity) {
    if (pid <= 0 || buffer == NULL || capacity <= 1) return 0;
    memset(buffer, 0, (size_t)capacity);
    return proc_pidpath(pid, buffer, (uint32_t)capacity);
}

int32_t KITTListGPUCounters(KITTGPUCounter *buffer, int32_t capacity) {
    if (buffer == NULL || capacity <= 0) return -1;
    io_iterator_t accelerators = IO_OBJECT_NULL;
    kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &accelerators);
    if (result != KERN_SUCCESS) return -1;
    int32_t count = 0;
    int32_t foundAccelerator = 0;
    io_service_t accelerator;
    while ((accelerator = IOIteratorNext(accelerators)) != IO_OBJECT_NULL) {
        foundAccelerator = 1;
        io_iterator_t clients = IO_OBJECT_NULL;
        result = IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &clients);
        IOObjectRelease(accelerator);
        if (result != KERN_SUCCESS) continue;
        io_service_t client;
        while ((client = IOIteratorNext(clients)) != IO_OBJECT_NULL) {
            CFTypeRef creator = IORegistryEntryCreateCFProperty(client, CFSTR("IOUserClientCreator"), kCFAllocatorDefault, 0);
            CFTypeRef usage = IORegistryEntryCreateCFProperty(client, CFSTR("AppUsage"), kCFAllocatorDefault, 0);
            int32_t pid = 0;
            int64_t nanoseconds = 0;
            int hasTime = 0;
            if (creator && CFGetTypeID(creator) == CFStringGetTypeID()) {
                char label[256] = {0};
                if (CFStringGetCString((CFStringRef)creator, label, sizeof(label), kCFStringEncodingUTF8)) {
                    int number = 0;
                    if (sscanf(label, "pid %d", &number) == 1) pid = number;
                }
            }
            if (usage && CFGetTypeID(usage) == CFArrayGetTypeID()) {
                CFArrayRef entries = (CFArrayRef)usage;
                for (CFIndex i = 0; i < CFArrayGetCount(entries); i++) {
                    CFTypeRef entry = CFArrayGetValueAtIndex(entries, i);
                    if (!entry || CFGetTypeID(entry) != CFDictionaryGetTypeID()) continue;
                    CFTypeRef value = CFDictionaryGetValue((CFDictionaryRef)entry, CFSTR("accumulatedGPUTime"));
                    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) {
                        int64_t part = 0;
                        CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &part);
                        if (part >= 0) {
                            hasTime = 1;
                            nanoseconds += part;
                        }
                    }
                }
            }
            if (pid > 0 && hasTime) {
                int32_t found = -1;
                for (int32_t j = 0; j < count; j++) if (buffer[j].pid == pid) { found = j; break; }
                if (found < 0 && count < capacity) {
                    found = count++;
                    buffer[found].pid = pid;
                    buffer[found].gpuNanoseconds = 0;
                }
                if (found >= 0) buffer[found].gpuNanoseconds += (uint64_t)nanoseconds;
            }
            if (creator) CFRelease(creator);
            if (usage) CFRelease(usage);
            IOObjectRelease(client);
        }
        IOObjectRelease(clients);
    }
    IOObjectRelease(accelerators);
    return foundAccelerator ? count : -1;
}
