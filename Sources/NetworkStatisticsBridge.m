#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>
#import <dlfcn.h>
#import "NetworkStatisticsBridge.h"

typedef void *KITTManagerRef;
typedef void *KITTSourceRef;
typedef void (^KITTSourceBlock)(KITTSourceRef);
typedef void (^KITTDictionaryBlock)(CFDictionaryRef);

typedef struct {
    KITTManagerRef (*create)(CFAllocatorRef, dispatch_queue_t, KITTSourceBlock);
    void (*destroy)(KITTManagerRef);
    void (*addTCP)(KITTManagerRef);
    void (*addUDP)(KITTManagerRef);
    void (*queryAll)(KITTManagerRef, dispatch_block_t);
    void (*queryDescription)(KITTSourceRef);
    void (*setDescription)(KITTSourceRef, KITTDictionaryBlock);
    void (*setCounts)(KITTSourceRef, KITTDictionaryBlock);
    void (*setRemoved)(KITTSourceRef, KITTSourceBlock);
    CFStringRef pidKey;
    CFStringRef receivedKey;
    CFStringRef sentKey;
} KITTNetworkAPI;

@interface KITTNetworkFlow : NSObject
@property(nonatomic) int32_t pid;
@property(nonatomic) uint64_t received;
@property(nonatomic) uint64_t sent;
@property(nonatomic) BOOL hasCounts;
@end

@implementation KITTNetworkFlow
@end

@interface KITTNetworkCollector : NSObject
- (BOOL)open;
- (int32_t)read:(KITTNetworkCounter *)buffer capacity:(int32_t)capacity;
- (void)close;
@end

@implementation KITTNetworkCollector {
    void *_library;
    KITTNetworkAPI _api;
    KITTManagerRef _manager;
    dispatch_queue_t _queue;
    NSMutableDictionary<NSValue *, KITTNetworkFlow *> *_flows;
    NSMutableDictionary<NSNumber *, KITTNetworkFlow *> *_retired;
    BOOL _queryPending;
    BOOL _closed;
}

static CFStringRef loadKey(void *library, const char *name) {
    CFStringRef *address = dlsym(library, name);
    return address ? *address : NULL;
}

- (BOOL)loadSymbols {
    _library = dlopen("/System/Library/PrivateFrameworks/NetworkStatistics.framework/Versions/A/NetworkStatistics", RTLD_LAZY | RTLD_LOCAL);
    if (!_library) return NO;
    _api.create = dlsym(_library, "NStatManagerCreate");
    _api.destroy = dlsym(_library, "NStatManagerDestroy");
    _api.addTCP = dlsym(_library, "NStatManagerAddAllTCP");
    _api.addUDP = dlsym(_library, "NStatManagerAddAllUDP");
    _api.queryAll = dlsym(_library, "NStatManagerQueryAllSourcesUpdate");
    _api.queryDescription = dlsym(_library, "NStatSourceQueryDescription");
    _api.setDescription = dlsym(_library, "NStatSourceSetDescriptionBlock");
    _api.setCounts = dlsym(_library, "NStatSourceSetCountsBlock");
    _api.setRemoved = dlsym(_library, "NStatSourceSetRemovedBlock");
    _api.pidKey = loadKey(_library, "kNStatSrcKeyPID");
    _api.receivedKey = loadKey(_library, "kNStatSrcKeyRxBytes");
    _api.sentKey = loadKey(_library, "kNStatSrcKeyTxBytes");
    return _api.create && _api.destroy && _api.addTCP && _api.addUDP && _api.queryAll &&
        _api.queryDescription && _api.setDescription && _api.setCounts && _api.setRemoved &&
        _api.pidKey && _api.receivedKey && _api.sentKey;
}

- (BOOL)open {
    _queue = dispatch_queue_create("dev.touchbarkitt.network-statistics", DISPATCH_QUEUE_SERIAL);
    _flows = [NSMutableDictionary dictionary];
    _retired = [NSMutableDictionary dictionary];
    if (![self loadSymbols]) {
        [self close];
        return NO;
    }
    __weak typeof(self) weakSelf = self;
    _manager = _api.create(kCFAllocatorDefault, _queue, ^(KITTSourceRef source) {
        [weakSelf addSource:source];
    });
    if (!_manager) {
        [self close];
        return NO;
    }
    _api.addTCP(_manager);
    _api.addUDP(_manager);
    return YES;
}

- (KITTNetworkFlow *)flow:(KITTSourceRef)source {
    NSValue *key = [NSValue valueWithPointer:source];
    KITTNetworkFlow *flow = _flows[key];
    if (!flow) {
        flow = [KITTNetworkFlow new];
        _flows[key] = flow;
    }
    return flow;
}

- (void)addSource:(KITTSourceRef)source {
    if (_closed) return;
    [self flow:source];
    __weak typeof(self) weakSelf = self;
    _api.setDescription(source, ^(CFDictionaryRef dictionary) {
        [weakSelf describe:source dictionary:dictionary];
    });
    _api.setCounts(source, ^(CFDictionaryRef dictionary) {
        [weakSelf count:source dictionary:dictionary];
    });
    _api.setRemoved(source, ^(KITTSourceRef removed) {
        [weakSelf removeSource:removed];
    });
    _api.queryDescription(source);
}

- (void)describe:(KITTSourceRef)source dictionary:(CFDictionaryRef)dictionary {
    if (_closed || !dictionary) return;
    CFTypeRef value = CFDictionaryGetValue(dictionary, _api.pidKey);
    if (!value || CFGetTypeID(value) != CFNumberGetTypeID()) return;
    int32_t pid = 0;
    if (CFNumberGetValue(value, kCFNumberSInt32Type, &pid) && pid > 0) {
        [self flow:source].pid = pid;
    }
}

- (void)count:(KITTSourceRef)source dictionary:(CFDictionaryRef)dictionary {
    if (_closed || !dictionary) return;
    CFTypeRef inValue = CFDictionaryGetValue(dictionary, _api.receivedKey);
    CFTypeRef outValue = CFDictionaryGetValue(dictionary, _api.sentKey);
    if (!inValue || !outValue || CFGetTypeID(inValue) != CFNumberGetTypeID() || CFGetTypeID(outValue) != CFNumberGetTypeID()) return;
    int64_t incoming = 0;
    int64_t outgoing = 0;
    CFNumberGetValue(inValue, kCFNumberSInt64Type, &incoming);
    CFNumberGetValue(outValue, kCFNumberSInt64Type, &outgoing);
    KITTNetworkFlow *flow = [self flow:source];
    flow.received = MAX(0, incoming);
    flow.sent = MAX(0, outgoing);
    flow.hasCounts = YES;
}

- (void)removeSource:(KITTSourceRef)source {
    if (_closed) return;
    NSValue *key = [NSValue valueWithPointer:source];
    KITTNetworkFlow *flow = _flows[key];
    if (flow && flow.pid > 0 && flow.hasCounts) {
        NSNumber *pid = @(flow.pid);
        KITTNetworkFlow *old = _retired[pid];
        if (!old) {
            old = [KITTNetworkFlow new];
            old.pid = flow.pid;
            _retired[pid] = old;
        }
        old.received += flow.received;
        old.sent += flow.sent;
    }
    [_flows removeObjectForKey:key];
}

- (int32_t)read:(KITTNetworkCounter *)buffer capacity:(int32_t)capacity {
    if (!buffer || capacity <= 0 || !_manager || _closed) return -1;
    __block int32_t count = 0;
    dispatch_sync(_queue, ^{
        NSMutableDictionary<NSNumber *, KITTNetworkFlow *> *totals = [NSMutableDictionary dictionary];
        for (KITTNetworkFlow *flow in _retired.allValues) {
            if (!flow.hasCounts && flow.received == 0 && flow.sent == 0) continue;
            KITTNetworkFlow *copy = [KITTNetworkFlow new];
            copy.pid = flow.pid;
            copy.received = flow.received;
            copy.sent = flow.sent;
            totals[@(flow.pid)] = copy;
        }
        for (KITTNetworkFlow *flow in _flows.allValues) {
            if (!flow.hasCounts || flow.pid <= 0) continue;
            NSNumber *pid = @(flow.pid);
            KITTNetworkFlow *total = totals[pid];
            if (!total) {
                total = [KITTNetworkFlow new];
                total.pid = flow.pid;
                totals[pid] = total;
            }
            total.received += flow.received;
            total.sent += flow.sent;
        }
        for (KITTNetworkFlow *flow in totals.allValues) {
            if (count >= capacity) break;
            buffer[count++] = (KITTNetworkCounter){flow.pid, flow.received, flow.sent};
        }
        if (!_queryPending) {
            _queryPending = YES;
            _api.queryAll(_manager, ^{
                _queryPending = NO;
            });
        }
    });
    return count;
}

- (void)close {
    if (_queue) {
        dispatch_sync(_queue, ^{
            _closed = YES;
        });
    }
    if (_manager && _api.destroy) _api.destroy(_manager);
    _manager = NULL;
    if (_queue) {
        dispatch_sync(_queue, ^{
            [_flows removeAllObjects];
            [_retired removeAllObjects];
            _queryPending = NO;
        });
    }
    if (_library) {
        dlclose(_library);
        _library = NULL;
    }
}
@end

void *KITTNetworkCreate(void) {
    KITTNetworkCollector *collector = [KITTNetworkCollector new];
    if (![collector open]) return NULL;
    return (__bridge_retained void *)collector;
}

int32_t KITTNetworkRead(void *handle, KITTNetworkCounter *output, int32_t capacity) {
    if (!handle) return -1;
    KITTNetworkCollector *collector = (__bridge KITTNetworkCollector *)handle;
    return [collector read:output capacity:capacity];
}

void KITTNetworkDestroy(void *handle) {
    if (!handle) return;
    KITTNetworkCollector *collector = (__bridge_transfer KITTNetworkCollector *)handle;
    [collector close];
}
