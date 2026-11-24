#import <Cocoa/Cocoa.h>

@interface NSTouchBarItem (PulsePrivate)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (PulsePrivate)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                        placement:(long long)placement
         systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

extern void DFRElementSetControlStripPresenceForIdentifier(NSTouchBarItemIdentifier identifier, BOOL present);
extern void DFRSystemModalShowsCloseBoxWhenFrontMost(BOOL shows);

#import "ProcessSamplingBridge.h"

#import "NetworkStatisticsBridge.h"
