#import "SVRApolloClient.h"
#import "AppListResponse.h"
#import "Connection.h"
#import "CryptoManager.h"
#import "PairManager.h"
#import "ServerInfoResponse.h"
#import "TemporaryApp.h"
#import "Utils.h"
#include <stdatomic.h>

@interface SVRApolloApplication ()
- (instancetype)initWithApp:(TemporaryApp *)app;
@end

@implementation SVRApolloApplication
- (instancetype)initWithApp:(TemporaryApp *)app {
    if ((self = [super init])) {
        _identifier = [app.id copy];
        _title = app.name.length ? [app.name copy] : _identifier;
    }
    return self;
}
@end

@interface SVRApolloPairResult : NSObject <PairCallback>
@property (nonatomic, copy) void (^showStatus)(NSString *);
@property (nonatomic, strong, nullable) NSData *certificate;
@property (nonatomic, copy, nullable) NSString *failure;
@end

@implementation SVRApolloPairResult
- (void)startPairing:(NSString *)pin {
    self.showStatus([NSString stringWithFormat:@"Digite o PIN %@ na aba PIN do Apollo no PC.", pin]);
}
- (void)pairSuccessful:(NSData *)serverCert { self.certificate = serverCert; }
- (void)alreadyPaired { self.failure = @"Remova o pareamento antigo deste StormVR no Apollo e tente de novo."; }
- (void)pairFailed:(NSString *)message { self.failure = message.length ? message : @"Falha no pareamento Apollo."; }
@end

@interface SVRApolloEvents : NSObject <ConnectionCallbacks>
@property (nonatomic, copy) void (^showStatus)(NSString *);
@end

@implementation SVRApolloEvents
- (void)connectionStarted { self.showStatus(@"Apollo conectado"); }
- (void)connectionTerminated:(int)errorCode {
    self.showStatus([NSString stringWithFormat:@"Transmissão Apollo encerrada (%d).", errorCode]);
}
- (void)stageStarting:(const char *)stageName { }
- (void)stageComplete:(const char *)stageName { }
- (void)stageFailed:(const char *)name withError:(int)error portTestFlags:(int)flags {
    self.showStatus([NSString stringWithFormat:@"Falha na conexão Apollo (%s, %d).", name, error]);
}
- (void)launchFailed:(NSString *)message { self.showStatus(message); }
- (void)videoContentShown { }
- (void)connectionStatusUpdate:(int)status { }
- (void)setHdrMode:(bool)enabled { }
- (void)rumble:(unsigned short)pad lowFreqMotor:(unsigned short)low highFreqMotor:(unsigned short)high { }
- (void)rumbleTriggers:(uint16_t)pad leftTrigger:(uint16_t)left rightTrigger:(uint16_t)right { }
- (void)setMotionEventState:(uint16_t)pad motionType:(uint8_t)type reportRateHz:(uint16_t)rate { }
- (void)setControllerLed:(uint16_t)pad r:(uint8_t)r g:(uint8_t)g b:(uint8_t)b { }
@end

@implementation SVRApolloClient {
    dispatch_queue_t _queue;
    atomic_uint_fast64_t _generation;
    atomic_bool _streamStarting;
    TemporaryHost *_host;
    Connection *_connection;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.stormvr.apollo", DISPATCH_QUEUE_SERIAL);
        atomic_init(&_generation, 0);
        atomic_init(&_streamStarting, false);
    }
    return self;
}

- (void (^)(NSString *))reporter:(void (^)(NSString *))status generation:(uint64_t)generation {
    __weak SVRApolloClient *owner = self;
    return ^(NSString *message) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SVRApolloClient *self = owner;
            if (self && atomic_load(&self->_generation) == generation) status(message);
        });
    };
}

- (void)prepareHost:(NSString *)address status:(void (^)(NSString *))status
       applications:(void (^)(NSArray<SVRApolloApplication *> *))applications {
    [self stop];
    uint64_t generation = atomic_fetch_add(&_generation, 1) + 1;
    void (^report)(NSString *) = [self reporter:status generation:generation];
    dispatch_async(_queue, ^{
        if (atomic_load(&self->_generation) != generation) return;
        self->_host = nil;
        report(@"Conectando ao Apollo…");
        [CryptoManager generateKeyPairUsingSSL];
        NSData *identity = [CryptoManager readCertFromFile];
        if (!identity.length) { report(@"Falha ao criar a identidade do StormVR."); return; }

        TemporaryHost *host = [[TemporaryHost alloc] init];
        host.activeAddress = address;
        NSString *certificateKey = [@"apollo.cert." stringByAppendingString:address];
        host.serverCert = [NSUserDefaults.standardUserDefaults dataForKey:certificateKey];
        HttpManager *client = [[HttpManager alloc] initWithHost:host];
        if (host.serverCert.length) {
            ServerInfoResponse *info = [[ServerInfoResponse alloc] init];
            [client executeRequestSynchronously:[HttpRequest requestForResponse:info withUrlRequest:[client newServerInfoRequest:true]]];
            if ([info isStatusOk]) [info populateHost:host];
        }
        if (host.pairState != PairStatePaired) {
            if (atomic_load(&self->_generation) != generation) return;
            SVRApolloPairResult *result = [[SVRApolloPairResult alloc] init];
            result.showStatus = report;
            PairManager *pair = [[PairManager alloc] initWithManager:client clientCert:identity callback:result];
            [pair main];
            if (atomic_load(&self->_generation) != generation) return;
            if (!result.certificate.length) { report(result.failure ?: @"Falha no pareamento Apollo."); return; }
            host.serverCert = result.certificate;
            [NSUserDefaults.standardUserDefaults setObject:result.certificate forKey:certificateKey];
        }
        if (atomic_load(&self->_generation) != generation) return;
        AppListResponse *response = [[AppListResponse alloc] init];
        [client executeRequestSynchronously:[HttpRequest requestForResponse:response withUrlRequest:[client newAppListRequest]]];
        if (![response isStatusOk]) { report(@"O Apollo não retornou a lista. Confira a permissão de aplicativos do cliente."); return; }

        NSMutableArray<SVRApolloApplication *> *list = [[NSMutableArray alloc] init];
        for (TemporaryApp *app in [response getAppList]) {
            if (app.id.length) [list addObject:[[SVRApolloApplication alloc] initWithApp:app]];
        }
        [list sortUsingComparator:^NSComparisonResult(SVRApolloApplication *a, SVRApolloApplication *b) {
            return [a.title localizedStandardCompare:b.title];
        }];
        self->_host = host;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (atomic_load(&self->_generation) == generation) applications([list copy]);
        });
        report(list.count ? @"Apollo pareado. Escolha o aplicativo do PC." : @"Nenhum aplicativo disponível no Apollo.");
    });
}

- (void)startApplication:(NSString *)identifier width:(int)width frame:(void (^)(CVPixelBufferRef))frame
                  status:(void (^)(NSString *))status {
    [self stop];
    uint64_t generation = atomic_fetch_add(&_generation, 1) + 1;
    void (^report)(NSString *) = [self reporter:status generation:generation];
    dispatch_async(_queue, ^{
        if (atomic_load(&self->_generation) != generation) return;
        TemporaryHost *host = self->_host;
        if (!host.serverCert.length) { report(@"Pareie o Apollo primeiro."); return; }
        HttpManager *client = [[HttpManager alloc] initWithHost:host];
        ServerInfoResponse *info = [[ServerInfoResponse alloc] init];
        [client executeRequestSynchronously:[HttpRequest requestForResponse:info withUrlRequest:[client newServerInfoRequest:false]]];
        NSString *state = [info getStringTag:@"state"];
        NSString *version = [info getStringTag:@"appversion"];
        if (![info isStatusOk] || !state.length || !version.length || ![[info getStringTag:@"PairStatus"] isEqualToString:@"1"]) {
            report(@"Não foi possível autenticar a conexão com o Apollo.");
            return;
        }
        if (atomic_load(&self->_generation) != generation) return;
        BOOL resume = [state hasSuffix:@"_SERVER_BUSY"];
        if (resume && ![[info getStringTag:@"currentgame"] isEqualToString:identifier]) {
            report(@"Há outro aplicativo em execução no Apollo. Encerre a sessão anterior no PC.");
            return;
        }
        StreamConfiguration *config = [[StreamConfiguration alloc] init];
        config.host = host.activeAddress;
        config.httpsPort = host.httpsPort;
        config.appVersion = version;
        config.gfeVersion = [info getStringTag:@"GfeVersion"];
        config.serverCodecModeSupport = [[info getStringTag:@"ServerCodecModeSupport"] intValue];
        config.serverCert = host.serverCert;
        config.appID = identifier;
        config.width = width;
        config.height = 1080;
        config.frameRate = 60;
        config.bitRate = 20000;
        config.riKey = [Utils randomBytes:16];
        config.riKeyId = (int)arc4random();
        config.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
        config.supportedVideoFormats = VIDEO_FORMAT_H264;

        HttpResponse *start = [[HttpResponse alloc] init];
        NSString *verb = resume ? @"resume" : @"launch";
        [client executeRequestSynchronously:[HttpRequest requestForResponse:start withUrlRequest:[client newLaunchOrResumeRequest:verb config:config]]];
        NSString *accepted = [start getStringTag:resume ? @"resume" : @"gamesession"];
        NSString *sessionURL = [start getStringTag:@"sessionUrl0"];
        if (![start isStatusOk] || !accepted.length || [accepted isEqualToString:@"0"] || !sessionURL.length) {
            report(@"O Apollo não iniciou a transmissão do aplicativo escolhido.");
            return;
        }
        if (atomic_load(&self->_generation) != generation) return;
        config.rtspSessionUrl = sessionURL;
        SVRApolloEvents *events = [[SVRApolloEvents alloc] init];
        events.showStatus = report;
        __weak SVRApolloClient *owner = self;
        VideoDecoderRenderer *renderer = [[VideoDecoderRenderer alloc] initWithFrameHandler:^(CVPixelBufferRef image) {
            SVRApolloClient *self = owner;
            if (self && atomic_load(&self->_generation) == generation) frame(image);
        }];
        self->_connection = [[Connection alloc] initWithConfig:config renderer:renderer connectionCallbacks:events];
        atomic_store(&self->_streamStarting, true);
        [self->_connection main];
        atomic_store(&self->_streamStarting, false);
    });
}

- (void)stop {
    atomic_fetch_add(&_generation, 1);
    if (atomic_load(&_streamStarting)) LiInterruptConnection();
    dispatch_async(_queue, ^{
        [self->_connection stopAndWait];
        self->_connection = nil;
    });
}
@end
