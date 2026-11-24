#import "include/VirtualDisplayBridge.h"

@interface VirtualDisplayManager ()
@property (nonatomic, readwrite) NSUInteger activeWidth;
@property (nonatomic, readwrite) NSUInteger activeHeight;
@end

@implementation VirtualDisplayManager

+ (instancetype)sharedManager {
    static VirtualDisplayManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VirtualDisplayManager alloc] init];
    });
    return instance;
}

- (BOOL)createVirtualDisplayWithWidth:(NSUInteger)width
                               height:(NSUInteger)height
                                hiDPI:(BOOL)hiDPI
                                 name:(NSString *)name {
    [self destroyVirtualDisplay];

    // Check if the runtime class exists
    Class descClass = NSClassFromString(@"CGVirtualDisplayDescriptor");
    Class displayClass = NSClassFromString(@"CGVirtualDisplay");
    Class modeClass = NSClassFromString(@"CGVirtualDisplayMode");
    Class settingsClass = NSClassFromString(@"CGVirtualDisplaySettings");

    if (!descClass || !displayClass || !modeClass || !settingsClass) {
        NSLog(@"[VirtualDisplay] CGVirtualDisplay private classes not found in runtime.");
        return NO;
    }

    CGVirtualDisplayDescriptor *descriptor = [[descClass alloc] init];
    descriptor.name = name ?: @"iMac 5K 扩展显示器";
    descriptor.maxPixelsWide = (unsigned int)(width * (hiDPI ? 2 : 1));
    descriptor.maxPixelsHigh = (unsigned int)(height * (hiDPI ? 2 : 1));
    descriptor.sizeInMillimeters = CGSizeMake(597, 336); // 27-inch 16:9 physical dimension
    descriptor.serialNum = 0x5432;
    descriptor.productID = 0x7890;
    descriptor.vendorID = 0x05ac; // Apple Vendor ID
    descriptor.queue = dispatch_get_main_queue();

    CGVirtualDisplay *display = [[displayClass alloc] initWithDescriptor:descriptor];
    if (!display) {
        NSLog(@"[VirtualDisplay] Failed to create CGVirtualDisplay instance.");
        return NO;
    }

    CGVirtualDisplayMode *mode = [[modeClass alloc] initWithWidth:width height:height refreshRate:60.0];
    CGVirtualDisplaySettings *settings = [[settingsClass alloc] init];
    settings.modes = @[mode];
    settings.hiDPI = hiDPI ? 1 : 0;

    if (![display applySettings:settings]) {
        NSLog(@"[VirtualDisplay] Failed to apply settings to virtual display.");
        return NO;
    }

    self.virtualDisplay = display;
    self.activeWidth = width * (hiDPI ? 2 : 1);
    self.activeHeight = height * (hiDPI ? 2 : 1);

    NSLog(@"[VirtualDisplay] Successfully created virtual display! ID: %u, resolution: %lux%lu (HiDPI: %d)",
          display.displayID, (unsigned long)self.activeWidth, (unsigned long)self.activeHeight, hiDPI);

    return YES;
}

- (CGDirectDisplayID)displayID {
    if (self.virtualDisplay) {
        return self.virtualDisplay.displayID;
    }
    return kCGNullDirectDisplay;
}

- (BOOL)isRunning {
    return self.virtualDisplay != nil;
}

- (void)destroyVirtualDisplay {
    if (self.virtualDisplay) {
        NSLog(@"[VirtualDisplay] Destroying virtual display ID: %u", self.virtualDisplay.displayID);
        self.virtualDisplay = nil;
        self.activeWidth = 0;
        self.activeHeight = 0;
    }
}

- (void)dealloc {
    [self destroyVirtualDisplay];
}

@end
