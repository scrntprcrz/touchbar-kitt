#ifndef KITT_NETWORK_STATISTICS_BRIDGE_H
#define KITT_NETWORK_STATISTICS_BRIDGE_H

#include <stdint.h>

typedef struct {
    int32_t pid;
    uint64_t received;
    uint64_t sent;
} KITTNetworkCounter;

void *KITTNetworkCreate(void);
int32_t KITTNetworkRead(void *handle, KITTNetworkCounter *output, int32_t capacity);
void KITTNetworkDestroy(void *handle);

#endif
