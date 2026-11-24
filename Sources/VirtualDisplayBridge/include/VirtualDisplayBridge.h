#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

@class CGVirtualDisplayDescriptor;

@interface CGVirtualDisplayMode : NSObject
@property (readonly, nonatomic) CGFloat refreshRate;
@property (readonly, nonatomic) NSUInteger width;
@property (readonly, nonatomic) NSUInteger height;
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(CGFloat)refreshRate;
@end

@interface CGVirtualDisplaySettings : NSObject
@property (retain, nonatomic) NSArray<CGVirtualDisplayMode *> *modes;
@property (nonatomic) unsigned int hiDPI;
- (instancetype)init;
@end

@interface CGVirtualDisplayDescriptor : NSObject
@property (retain, nonatomic) dispatch_queue_t queue;
@property (retain, nonatomic) NSString *name;
@property (nonatomic) unsigned int maxPixelsHigh;
@property (nonatomic) unsigned int maxPixelsWide;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int serialNum;
@property (nonatomic) unsigned int productID;
@property (nonatomic) unsigned int vendorID;
@property (copy, nonatomic) void (^terminationHandler)(id _Nullable, id _Nullable);
- (instancetype)init;
@end

@interface CGVirtualDisplay : NSObject
@property (readonly, nonatomic) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

@interface VirtualDisplayManager : NSObject

@property (nonatomic, strong, nullable) CGVirtualDisplay *virtualDisplay;
@property (nonatomic, readonly) CGDirectDisplayID displayID;
@property (nonatomic, readonly) BOOL isRunning;
@property (nonatomic, readonly) NSUInteger activeWidth;
@property (nonatomic, readonly) NSUInteger activeHeight;

+ (instancetype)sharedManager;

- (BOOL)createVirtualDisplayWithWidth:(NSUInteger)width
                               height:(NSUInteger)height
                                hiDPI:(BOOL)hiDPI
                                 name:(NSString *)name;

- (void)destroyVirtualDisplay;

@end

NS_ASSUME_NONNULL_END
