#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

@interface SVRApolloApplication : NSObject
@property (nonatomic, readonly) NSString *identifier;
@property (nonatomic, readonly) NSString *title;
@end

@interface SVRApolloClient : NSObject
- (void)prepareHost:(NSString *)host
              status:(void (^)(NSString *status))status
          applications:(void (^)(NSArray<SVRApolloApplication *> *applications))applications
    NS_SWIFT_NAME(prepare(host:status:applications:));
- (void)startApplication:(NSString *)identifier
                    frame:(void (^)(CVPixelBufferRef frame))frame
                   status:(void (^)(NSString *status))status
    NS_SWIFT_NAME(start(application:frame:status:));
- (void)stop;
@end

NS_ASSUME_NONNULL_END
