#import "FlutterMimcPlugin.h"

#import <MMCSDK/MMCSDK.h>

static NSString *const kMethodsChannel = @"dev.flutter_mimc/methods";
static NSString *const kEventsChannel = @"dev.flutter_mimc/events";

@interface FlutterMimcPlugin () <parseTokenDelegate,
                                 onlineStatusDelegate,
                                 handleMessageDelegate,
                                 handleUnlimitedGroupDelegate,
                                 handleRtsCallDelegate,
                                 handleRtsChannelDelegate>
@property(nonatomic, strong) MCUser *user;
@property(nonatomic, copy) NSString *token;
@property(nonatomic, copy) FlutterEventSink eventSink;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, FlutterResult> *pendingCreates;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, FlutterResult> *pendingJoins;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, FlutterResult> *pendingQuits;
@property(nonatomic, strong) NSMutableDictionary<NSNumber *, FlutterResult> *pendingDismisses;
@property(nonatomic, assign) int64_t nextRequestId;
@property(nonatomic, assign) BOOL acceptIncomingRtsCalls;
@property(nonatomic, copy) NSString *incomingRtsDescription;
@property(nonatomic, strong) NSMutableSet<NSNumber *> *rtsChannelIds;
@end

@implementation FlutterMimcPlugin

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar> *)registrar {
  FlutterMimcPlugin *instance = [[FlutterMimcPlugin alloc] init];
  FlutterMethodChannel *methods =
      [FlutterMethodChannel methodChannelWithName:kMethodsChannel
                                  binaryMessenger:registrar.messenger];
  FlutterEventChannel *events =
      [FlutterEventChannel eventChannelWithName:kEventsChannel
                                binaryMessenger:registrar.messenger];
  [registrar addMethodCallDelegate:instance channel:methods];
  [events setStreamHandler:instance];
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _token = @"";
    _nextRequestId = 1;
    _pendingCreates = [NSMutableDictionary dictionary];
    _pendingJoins = [NSMutableDictionary dictionary];
    _pendingQuits = [NSMutableDictionary dictionary];
    _pendingDismisses = [NSMutableDictionary dictionary];
    _acceptIncomingRtsCalls = NO;
    _incomingRtsDescription = @"Rejected by application policy";
    _rtsChannelIds = [NSMutableSet set];
  }
  return self;
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
  NSDictionary *arguments = [call.arguments isKindOfClass:NSDictionary.class]
                                ? call.arguments
                                : @{};
  @try {
    if ([call.method isEqualToString:@"getCapabilities"]) {
      result(@[ @"message", @"groupMessage", @"onlineMessage",
                @"unlimitedGroup", @"offlinePull", @"realtimeStream",
                @"realtimeChannel" ]);
    } else if ([call.method isEqualToString:@"initialize"]) {
      [self initializeWithArguments:arguments result:result];
    } else if ([call.method isEqualToString:@"updateToken"]) {
      NSString *token = [self requiredString:arguments key:@"token"];
      self.token = token;
      result(nil);
    } else if ([call.method isEqualToString:@"login"]) {
      [self completeBooleanRequest:[[self requiredUser] login]
                            result:result
                         operation:@"login"];
    } else if ([call.method isEqualToString:@"logout"]) {
      [self completeBooleanRequest:[[self requiredUser] logout]
                            result:result
                         operation:@"logout"];
    } else if ([call.method isEqualToString:@"isOnline"]) {
      result(@([[self requiredUser] isOnline]));
    } else if ([call.method isEqualToString:@"sendMessage"]) {
      NSString *packetId = [[self requiredUser]
          sendMessage:[self requiredString:arguments key:@"toAccount"]
              payload:[self requiredData:arguments]
              bizType:[self optionalString:arguments key:@"bizType"]
              isStore:[self optionalBool:arguments key:@"store" fallback:YES]];
      result(packetId ?: @"");
    } else if ([call.method isEqualToString:@"sendGroupMessage"]) {
      NSString *packetId = [[self requiredUser]
          sendGroupMessage:[self requiredInt64:arguments key:@"topicId"]
                    payload:[self requiredData:arguments]
                   bizType:[self optionalString:arguments key:@"bizType"]
                   isStore:[self optionalBool:arguments key:@"store" fallback:YES]];
      result(packetId ?: @"");
    } else if ([call.method isEqualToString:@"sendOnlineMessage"]) {
      NSString *packetId = [[self requiredUser]
          sendOnlineMessage:[self requiredString:arguments key:@"toAccount"]
                    payload:[self requiredData:arguments]
                   bizType:[self optionalString:arguments key:@"bizType"]];
      result(packetId ?: @"");
    } else if ([call.method isEqualToString:@"sendUnlimitedGroupMessage"]) {
      NSString *packetId = [[self requiredUser]
          sendUnlimitedGroupMessage:[self requiredInt64:arguments key:@"topicId"]
                            payload:[self requiredData:arguments]
                           bizType:[self optionalString:arguments key:@"bizType"]
                           isStore:[self optionalBool:arguments key:@"store" fallback:YES]];
      result(packetId ?: @"");
    } else if ([call.method isEqualToString:@"createUnlimitedGroup"]) {
      MCUser *user = [self requiredUser];
      NSString *topicName = [self requiredString:arguments key:@"topicName"];
      NSNumber *requestId = [self nextRequestKey];
      [self storeResult:result forKey:requestId inPending:self.pendingCreates];
      @try {
        BOOL queued = [user createUnlimitedGroup:topicName context:requestId];
        if (!queued) {
          FlutterResult pending =
              [self takeResultForKey:requestId fromPending:self.pendingCreates];
          if (pending != nil) {
            pending([FlutterError errorWithCode:@"uc_create_not_queued"
                                        message:@"Create request was not queued"
                                        details:nil]);
          }
        }
      } @catch (NSException *exception) {
        [self takeResultForKey:requestId fromPending:self.pendingCreates];
        @throw;
      }
    } else if ([call.method isEqualToString:@"joinUnlimitedGroup"]) {
      MCUser *user = [self requiredUser];
      int64_t topicId = [self requiredInt64:arguments key:@"topicId"];
      NSNumber *requestId = [self nextRequestKey];
      [self storeResult:result forKey:requestId inPending:self.pendingJoins];
      @try {
        NSString *packetId = [user joinUnlimitedGroup:topicId context:requestId];
        if (packetId.length == 0) {
          FlutterResult pending =
              [self takeResultForKey:requestId fromPending:self.pendingJoins];
          if (pending != nil) {
            pending([FlutterError errorWithCode:@"uc_join_not_queued"
                                        message:@"Join request was not queued"
                                        details:nil]);
          }
        }
      } @catch (NSException *exception) {
        [self takeResultForKey:requestId fromPending:self.pendingJoins];
        @throw;
      }
    } else if ([call.method isEqualToString:@"quitUnlimitedGroup"]) {
      MCUser *user = [self requiredUser];
      int64_t topicId = [self requiredInt64:arguments key:@"topicId"];
      NSNumber *requestId = [self nextRequestKey];
      [self storeResult:result forKey:requestId inPending:self.pendingQuits];
      @try {
        NSString *packetId = [user quitUnlimitedGroup:topicId context:requestId];
        if (packetId.length == 0) {
          FlutterResult pending =
              [self takeResultForKey:requestId fromPending:self.pendingQuits];
          if (pending != nil) {
            pending([FlutterError errorWithCode:@"uc_quit_not_queued"
                                        message:@"Quit request was not queued"
                                        details:nil]);
          }
        }
      } @catch (NSException *exception) {
        [self takeResultForKey:requestId fromPending:self.pendingQuits];
        @throw;
      }
    } else if ([call.method isEqualToString:@"dismissUnlimitedGroup"]) {
      MCUser *user = [self requiredUser];
      int64_t topicId = [self requiredInt64:arguments key:@"topicId"];
      NSNumber *requestId = [self nextRequestKey];
      [self storeResult:result forKey:requestId inPending:self.pendingDismisses];
      @try {
        BOOL queued = [user dismissUnlimitedGroup:topicId context:requestId];
        if (!queued) {
          FlutterResult pending =
              [self takeResultForKey:requestId fromPending:self.pendingDismisses];
          if (pending != nil) {
            pending([FlutterError errorWithCode:@"uc_dismiss_not_queued"
                                        message:@"Dismiss request was not queued"
                                        details:nil]);
          }
        }
      } @catch (NSException *exception) {
        [self takeResultForKey:requestId fromPending:self.pendingDismisses];
        @throw;
      }
    } else if ([call.method isEqualToString:@"setRtsIncomingCallPolicy"]) {
      [self requiredUser];
      self.acceptIncomingRtsCalls =
          [[self requiredString:arguments key:@"policy"] isEqualToString:@"accept"];
      self.incomingRtsDescription =
          [self optionalString:arguments key:@"description"];
      result(nil);
    } else if ([call.method isEqualToString:@"configureRtsStream"]) {
      [self configureRtsStream:arguments];
      result(nil);
    } else if ([call.method isEqualToString:@"configureRtsBuffers"]) {
      MCUser *user = [self requiredUser];
      int sendSize = [self requiredInt:arguments key:@"sendSize" minimum:1];
      int receiveSize =
          [self requiredInt:arguments key:@"receiveSize" minimum:1];
      [user setSendBufferSize:sendSize];
      [user setRecvBufferSize:receiveSize];
      result(nil);
    } else if ([call.method isEqualToString:@"getRtsBufferState"]) {
      MCUser *user = [self requiredUser];
      result(@{
        @"sendSize" : @([user getSendBufferSize]),
        @"receiveSize" : @([user getRecvBufferSize]),
        @"sendUsageRate" : @([user getSendBufferUsageRate]),
        @"receiveUsageRate" : @([user getRecvBufferUsageRate]),
      });
    } else if ([call.method isEqualToString:@"clearRtsBuffers"]) {
      MCUser *user = [self requiredUser];
      [user clearSendBuffer];
      [user clearRecvBuffer];
      result(nil);
    } else if ([call.method isEqualToString:@"dialRtsCall"]) {
      MCUser *user = [self requiredUser];
      NSString *toAccount = [self requiredString:arguments key:@"toAccount"];
      NSString *toResource = [self optionalString:arguments key:@"toResource"];
      int64_t callId = [user dialCall:toAccount
                           toResource:toResource
                           appContent:[self optionalData:arguments key:@"appContent"]];
      if (callId < 0) {
        // The legacy Xiaomi SDK may return stale NSString pointers from
        // getResource/getUuid on this failure path. Retaining either object can
        // crash in objc_msgSend before Flutter receives the platform error.
        NSDictionary *details = @{
          @"failureCode" : @(callId),
          @"online" : @([user isOnline]),
          @"relayLinkState" : @([user getRelayLinkState]),
          @"relayConnId" : @([user getRelayConnId]),
          @"maxRtsCallCount" : @([user getMaxRtsCallCount]),
          @"toAccount" : toAccount,
          @"toResource" : toResource ?: @"",
        };
        NSLog(@"flutter_mimc RTS dial failed: %@", details);
        result([FlutterError errorWithCode:@"rts_dial_failed"
                                  message:@"RTS call was not queued"
                                  details:details]);
      } else {
        result(@(callId));
      }
    } else if ([call.method isEqualToString:@"closeRtsCall"]) {
      [[self requiredUser]
          closeCall:[self requiredPositiveInt64:arguments key:@"callId"]
          byeReason:[self optionalString:arguments key:@"reason"]];
      result(nil);
    } else if ([call.method isEqualToString:@"sendRtsData"]) {
      [self sendRtsData:arguments result:result];
    } else if ([call.method isEqualToString:@"createRtsChannel"]) {
      int64_t identity = [[self requiredUser]
          createChannel:[self optionalData:arguments key:@"extra"]];
      if (identity < 0) {
        result([FlutterError errorWithCode:@"rts_channel_create_failed"
                                  message:@"RTS channel was not queued"
                                  details:nil]);
      } else {
        result(@(identity));
      }
    } else if ([call.method isEqualToString:@"joinRtsChannel"]) {
      [[self requiredUser]
          joinChannel:[self requiredPositiveInt64:arguments key:@"callId"]
              callKey:[self requiredString:arguments key:@"callKey"]];
      result(nil);
    } else if ([call.method isEqualToString:@"leaveRtsChannel"]) {
      [[self requiredUser]
          leaveChannel:[self requiredPositiveInt64:arguments key:@"callId"]
               callKey:[self requiredString:arguments key:@"callKey"]];
      result(nil);
    } else if ([call.method isEqualToString:@"getRtsChannelMembers"]) {
      NSArray<MIMCChannelUser *> *members = [[self requiredUser]
          getChannelUsers:[self requiredPositiveInt64:arguments key:@"callId"]];
      NSMutableArray *mapped = [NSMutableArray arrayWithCapacity:members.count];
      for (MIMCChannelUser *member in members) {
        [mapped addObject:[self channelMemberMap:member]];
      }
      result(mapped);
    } else if ([call.method isEqualToString:@"dispose"]) {
      [self disposeUser];
      result(nil);
    } else {
      result(FlutterMethodNotImplemented);
    }
  } @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"ios_error"
                                message:exception.reason
                                details:nil]);
  }
}

- (void)initializeWithArguments:(NSDictionary *)arguments
                         result:(FlutterResult)result {
  int64_t appId = [self requiredInt64:arguments key:@"appId"];
  NSString *account = [self requiredString:arguments key:@"appAccount"];
  NSString *resource = [self optionalString:arguments key:@"resource"];
  NSString *initialToken = [self requiredString:arguments key:@"token"];

  [self disposeUser];
  self.acceptIncomingRtsCalls =
      [[self optionalString:arguments key:@"rtsIncomingCallPolicy"]
          isEqualToString:@"accept"];
  self.incomingRtsDescription =
      [self optionalString:arguments key:@"rtsIncomingCallDescription"];

  MCUser *user = resource.length > 0
                     ? [[MCUser alloc] initWithAppId:appId
                                      andAppAccount:account
                                        andResource:resource]
                     : [[MCUser alloc] initWithAppId:appId
                                      andAppAccount:account];
  if (user == nil) {
    result([FlutterError errorWithCode:@"create_user_failed"
                                message:@"MCUser initialization returned nil"
                                details:nil]);
    return;
  }
  self.token = initialToken;
  user.parseTokenDelegate = self;
  user.onlineStatusDelegate = self;
  user.handleMessageDelegate = self;
  user.handleUnlimitedGroupDelegate = self;
  user.handleRtsCallDelegate = self;
  user.handleRtsChannelDelegate = self;
  [MCUser setMIMCLogSwitch:[self optionalBool:arguments key:@"debug" fallback:NO]];
  self.user = user;
  result(nil);
}

- (MCUser *)requiredUser {
  if (self.user == nil) {
    [NSException raise:@"MIMCNotInitialized"
                format:@"MIMC is not initialized"];
  }
  return self.user;
}

- (void)completeBooleanRequest:(BOOL)accepted
                        result:(FlutterResult)result
                     operation:(NSString *)operation {
  if (accepted) {
    result(nil);
  } else {
    result([FlutterError
        errorWithCode:[operation stringByAppendingString:@"_not_queued"]
               message:[NSString stringWithFormat:@"MIMC rejected %@", operation]
               details:nil]);
  }
}

- (NSString *)requiredString:(NSDictionary *)arguments key:(NSString *)key {
  id value = arguments[key];
  if (![value isKindOfClass:NSString.class] || [value length] == 0) {
    [NSException raise:@"MIMCInvalidArgument" format:@"%@ is required", key];
  }
  return value;
}

- (NSString *)optionalString:(NSDictionary *)arguments key:(NSString *)key {
  id value = arguments[key];
  return [value isKindOfClass:NSString.class] ? value : @"";
}

- (int64_t)requiredInt64:(NSDictionary *)arguments key:(NSString *)key {
  id value = arguments[key];
  if ([value isKindOfClass:NSNumber.class]) {
    return [value longLongValue];
  }
  if ([value isKindOfClass:NSString.class]) {
    NSScanner *scanner = [NSScanner scannerWithString:value];
    long long parsed = 0;
    if ([scanner scanLongLong:&parsed] && scanner.isAtEnd) {
      return parsed;
    }
  }
  [NSException raise:@"MIMCInvalidArgument"
              format:@"%@ must be an integer", key];
  return 0;
}

- (BOOL)optionalBool:(NSDictionary *)arguments
                  key:(NSString *)key
             fallback:(BOOL)fallback {
  id value = arguments[key];
  return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}

- (int)requiredInt:(NSDictionary *)arguments
               key:(NSString *)key
           minimum:(int)minimum {
  id value = arguments[key];
  if (![value isKindOfClass:NSNumber.class] || [value intValue] < minimum) {
    [NSException raise:@"MIMCInvalidArgument"
                format:@"%@ must be >= %d", key, minimum];
  }
  return [value intValue];
}

- (int64_t)requiredPositiveInt64:(NSDictionary *)arguments
                              key:(NSString *)key {
  int64_t value = [self requiredInt64:arguments key:key];
  if (value <= 0) {
    [NSException raise:@"MIMCInvalidArgument"
                format:@"%@ must be greater than zero", key];
  }
  return value;
}

- (NSData *)requiredData:(NSDictionary *)arguments {
  id value = arguments[@"payload"];
  if ([value isKindOfClass:FlutterStandardTypedData.class]) {
    return [value data];
  }
  if ([value isKindOfClass:NSData.class]) {
    return value;
  }
  [NSException raise:@"MIMCInvalidArgument" format:@"payload is required"];
  return nil;
}

- (NSData *)optionalData:(NSDictionary *)arguments key:(NSString *)key {
  id value = arguments[key];
  if ([value isKindOfClass:FlutterStandardTypedData.class]) {
    return [value data];
  }
  if ([value isKindOfClass:NSData.class]) {
    return value;
  }
  return NSData.data;
}

- (void)configureRtsStream:(NSDictionary *)arguments {
  NSString *strategyName = [self requiredString:arguments key:@"strategy"];
  int strategy;
  if ([strategyName isEqualToString:@"fec"]) {
    strategy = STRATEGY_FEC;
  } else if ([strategyName isEqualToString:@"ack"]) {
    strategy = STRATEGY_ACK;
  } else {
    [NSException raise:@"MIMCInvalidArgument"
                format:@"Unknown RTS stream strategy"];
    return;
  }
  MIMCStreamConfig *config = [[MIMCStreamConfig alloc]
      initWithStrategy:strategy
      andAckWaitTimeMs:[self requiredInt:arguments
                                         key:@"ackWaitTimeMs"
                                     minimum:0]
      andIsEncrypt:[self optionalBool:arguments key:@"encrypt" fallback:YES]];
  NSString *dataType = [self requiredString:arguments key:@"dataType"];
  if ([dataType isEqualToString:@"audio"]) {
    [[self requiredUser] initAudioStreamConfig:config];
  } else if ([dataType isEqualToString:@"video"]) {
    [[self requiredUser] initVideoStreamConfig:config];
  } else {
    [NSException raise:@"MIMCInvalidArgument" format:@"Unknown RTS data type"];
  }
}

- (void)sendRtsData:(NSDictionary *)arguments result:(FlutterResult)result {
  NSString *dataTypeName = [self requiredString:arguments key:@"dataType"];
  RtsDataType dataType;
  if ([dataTypeName isEqualToString:@"audio"]) {
    dataType = AUDIO;
  } else if ([dataTypeName isEqualToString:@"video"]) {
    dataType = VIDEO;
  } else {
    [NSException raise:@"MIMCInvalidArgument" format:@"Unknown RTS data type"];
    return;
  }

  NSString *priorityName = [self requiredString:arguments key:@"priority"];
  MIMCDataPriority priority;
  if ([priorityName isEqualToString:@"p0"]) {
    priority = MIMC_P0;
  } else if ([priorityName isEqualToString:@"p1"]) {
    priority = MIMC_P1;
  } else if ([priorityName isEqualToString:@"p2"]) {
    priority = MIMC_P2;
  } else {
    [NSException raise:@"MIMCInvalidArgument" format:@"Unknown RTS priority"];
    return;
  }

  MCUser *user = [self requiredUser];
  int64_t callId = [self requiredPositiveInt64:arguments key:@"callId"];
  NSData *payload = [self requiredData:arguments];
  BOOL canBeDropped =
      [self optionalBool:arguments key:@"canBeDropped" fallback:NO];
  int resendCount =
      [self requiredInt:arguments key:@"resendCount" minimum:0];
  NSString *context = [self optionalString:arguments key:@"context"];
  NSDictionary *sdkContext = @{
    @"value" : context,
    @"channel" : @([self isRtsChannel:callId]),
  };
  NSString *channelName =
      [self requiredString:arguments key:@"channelType"];
  int dataId;
  if ([channelName isEqualToString:@"automatic"]) {
    dataId = [user sendRtsData:callId
                          data:payload
                      dataType:dataType
                  dataPriority:priority
                  canBeDropped:canBeDropped
                   resendCount:resendCount
                       context:sdkContext];
  } else {
    RtsChannelType channelType;
    if ([channelName isEqualToString:@"relay"]) {
      channelType = RELAY;
    } else if ([channelName isEqualToString:@"p2pInternet"]) {
      channelType = P2P_INTERNET;
    } else if ([channelName isEqualToString:@"p2pIntranet"]) {
      channelType = P2P_INTRANET;
    } else {
      [NSException raise:@"MIMCInvalidArgument"
                  format:@"Unknown RTS channel type"];
      return;
    }
    dataId = [user sendRtsData:callId
                          data:payload
                      dataType:dataType
                  dataPriority:priority
                  canBeDropped:canBeDropped
                   resendCount:resendCount
                   channelType:channelType
                       context:sdkContext];
  }
  if (dataId < 0) {
    result([FlutterError errorWithCode:@"rts_send_failed"
                                message:@"RTS data was not queued"
                                details:nil]);
  } else {
    result(@(dataId));
  }
}

- (void)disposeUser {
  if (self.user != nil) {
    [self.user logout];
    [self.user destroy];
    self.user = nil;
  }
  self.token = @"";
  self.acceptIncomingRtsCalls = NO;
  self.incomingRtsDescription = @"Rejected by application policy";
  @synchronized(self) {
    [self.rtsChannelIds removeAllObjects];
  }
  [self failAndClear:self.pendingCreates];
  [self failAndClear:self.pendingJoins];
  [self failAndClear:self.pendingQuits];
  [self failAndClear:self.pendingDismisses];
}

- (NSDictionary *)channelMemberMap:(MIMCChannelUser *)member {
  return @{
    @"appAccount" : [member getAppAccount] ?: @"",
    @"resource" : [member getResource] ?: @"",
  };
}

- (void)setRtsChannel:(int64_t)callId active:(BOOL)active {
  @synchronized(self) {
    if (active) {
      [self.rtsChannelIds addObject:@(callId)];
    } else {
      [self.rtsChannelIds removeObject:@(callId)];
    }
  }
}

- (BOOL)isRtsChannel:(int64_t)callId {
  @synchronized(self) {
    return [self.rtsChannelIds containsObject:@(callId)];
  }
}

- (void)failAndClear:(NSMutableDictionary<NSNumber *, FlutterResult> *)pending {
  NSArray *results;
  @synchronized(self) {
    results = pending.allValues;
    [pending removeAllObjects];
  }
  for (id value in results) {
    FlutterResult result = value;
    [self runOnMain:^{
      result([FlutterError errorWithCode:@"disposed"
                                  message:@"MIMC user was disposed"
                                  details:nil]);
    }];
  }
}

- (NSNumber *)nextRequestKey {
  @synchronized(self) {
    return @(self.nextRequestId++);
  }
}

- (void)storeResult:(FlutterResult)result
              forKey:(NSNumber *)key
           inPending:(NSMutableDictionary<NSNumber *, FlutterResult> *)pending {
  @synchronized(self) {
    pending[key] = [result copy];
  }
}

- (FlutterResult)takeResultForKey:(NSNumber *)key
                       fromPending:(NSMutableDictionary<NSNumber *, FlutterResult> *)pending {
  if (key == nil) return nil;
  @synchronized(self) {
    FlutterResult result = pending[key];
    [pending removeObjectForKey:key];
    return result;
  }
}

- (void)emitType:(NSString *)type data:(NSDictionary *)data {
  [self runOnMain:^{
    if (self.eventSink != nil) {
      self.eventSink(@{ @"type" : type, @"data" : data ?: @{} });
    }
  }];
}

- (void)runOnMain:(dispatch_block_t)block {
  if (NSThread.isMainThread) {
    block();
  } else {
    dispatch_async(dispatch_get_main_queue(), block);
  }
}

- (NSDictionary *)messageMap:(MIMCMessage *)message channel:(NSString *)channel {
  return @{
    @"packetId" : [message getPacketId] ?: @"",
    @"sequence" : @([message getSequence]),
    @"timestamp" : @([message getTimestamp]),
    @"fromAccount" : [message getFromAccount] ?: @"",
    @"fromResource" : [message getFromResource] ?: @"",
    @"toAccount" : [message getToAccount] ?: @"",
    @"toResource" : [message getToResource] ?: @"",
    @"payload" : [FlutterStandardTypedData typedDataWithBytes:[message getPayload]],
    @"bizType" : [message getBizType] ?: @"",
    @"channel" : channel,
  };
}

- (NSDictionary *)groupMessageMap:(MIMCGroupMessage *)message
                           channel:(NSString *)channel {
  return @{
    @"packetId" : [message getPacketId] ?: @"",
    @"sequence" : @([message getSequence]),
    @"timestamp" : @([message getTimestamp]),
    @"fromAccount" : [message getFromAccount] ?: @"",
    @"fromResource" : [message getFromResource] ?: @"",
    @"topicId" : @([message getTopicId]),
    @"payload" : [FlutterStandardTypedData typedDataWithBytes:[message getPayload]],
    @"bizType" : [message getBizType] ?: @"",
    @"channel" : channel,
  };
}

#pragma mark - SDK delegates

- (void)parseProxyServiceToken:(void (^)(NSData *))callback {
  NSData *data = [(self.token ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
  callback(data ?: NSData.data);
}

- (void)statusChange:(MCUser *)user
               status:(int)status
                 type:(NSString *)type
               reason:(NSString *)reason
                 desc:(NSString *)desc {
  [self emitType:@"connectionChanged"
            data:@{
              @"state" : status == Online ? @"online" : @"offline",
              @"reason" : reason ?: @"",
              @"description" : desc ?: @"",
            }];
  NSString *text = [NSString stringWithFormat:@"%@ %@ %@", type ?: @"",
                                                     reason ?: @"", desc ?: @""];
  if ([[text lowercaseString] containsString:@"token"]) {
    [self emitType:@"tokenRefreshRequired" data:@{}];
  }
}

- (BOOL)handleMessage:(NSArray<MIMCMessage *> *)packets user:(MCUser *)user {
  for (MIMCMessage *message in packets) {
    [self emitType:@"message" data:[self messageMap:message channel:@"direct"]];
  }
  return YES;
}

- (BOOL)handleGroupMessage:(NSArray<MIMCGroupMessage *> *)packets {
  for (MIMCGroupMessage *message in packets) {
    [self emitType:@"groupMessage"
              data:[self groupMessageMap:message channel:@"group"]];
  }
  return YES;
}

- (BOOL)handleUnlimitedGroupMessage:(NSArray<MIMCGroupMessage *> *)packets {
  for (MIMCGroupMessage *message in packets) {
    [self emitType:@"unlimitedGroupMessage"
              data:[self groupMessageMap:message channel:@"unlimitedGroup"]];
  }
  return YES;
}

- (BOOL)onPullNotification {
  [self emitType:@"offlinePullNotification" data:@{}];
  return YES;
}

- (void)handleOnlineMessage:(MIMCMessage *)message {
  [self emitType:@"onlineMessage" data:[self messageMap:message channel:@"online"]];
}

- (void)handleServerAck:(MIMCServerAck *)ack {
  [self emitType:@"serverAck"
            data:@{
              @"packetId" : [ack getPacketId] ?: @"",
              @"sequence" : @([ack getSequence]),
              @"timestamp" : @([ack getTimestamp]),
              @"code" : @([ack getCode]),
              @"description" : [ack getDesc] ?: @"",
            }];
}

- (void)handleOnlineMessageAck:(MCOnlineMessageAck *)ack {
  [self emitType:@"serverAck"
            data:@{
              @"packetId" : [ack getPacketId] ?: @"",
              @"code" : @([ack getCode]),
              @"description" : [ack getDesc] ?: @"",
            }];
}

- (void)handleSendMessageTimeout:(MIMCMessage *)message {
  [self emitType:@"sendMessageTimeout"
            data:[self messageMap:message channel:@"direct"]];
}

- (void)handleSendGroupMessageTimeout:(MIMCGroupMessage *)message {
  [self emitType:@"sendGroupMessageTimeout"
            data:[self groupMessageMap:message channel:@"group"]];
}

- (void)handleSendUnlimitedGroupMessageTimeout:(MIMCGroupMessage *)message {
  [self emitType:@"sendUnlimitedGroupMessageTimeout"
            data:[self groupMessageMap:message channel:@"unlimitedGroup"]];
}

- (void)handleCreateUnlimitedGroup:(int64_t)topicId
                          topicName:(NSString *)topicName
                               code:(int)code
                               desc:(NSString *)desc
                            context:(id)context {
  NSNumber *key = [context isKindOfClass:NSNumber.class] ? context : nil;
  FlutterResult result = [self takeResultForKey:key fromPending:self.pendingCreates];
  [self complete:result operation:@"uc_create" code:code description:desc value:@(topicId)];
}

- (void)handleJoinUnlimitedGroup:(int64_t)topicId
                             code:(int)code
                             desc:(NSString *)desc
                          context:(id)context {
  NSNumber *key = [context isKindOfClass:NSNumber.class] ? context : nil;
  FlutterResult result = [self takeResultForKey:key fromPending:self.pendingJoins];
  [self complete:result operation:@"uc_join" code:code description:desc value:nil];
}

- (void)handleQuitUnlimitedGroup:(int64_t)topicId
                             code:(int)code
                             desc:(NSString *)desc
                          context:(id)context {
  NSNumber *key = [context isKindOfClass:NSNumber.class] ? context : nil;
  FlutterResult result = [self takeResultForKey:key fromPending:self.pendingQuits];
  [self complete:result operation:@"uc_quit" code:code description:desc value:nil];
}

- (void)handleDismissUnlimitedGroup:(int64_t)topicId
                                code:(int)code
                                desc:(NSString *)desc
                             context:(id)context {
  NSNumber *key = [context isKindOfClass:NSNumber.class] ? context : nil;
  FlutterResult result = [self takeResultForKey:key fromPending:self.pendingDismisses];
  [self complete:result operation:@"uc_dismiss" code:code description:desc value:nil];
}

- (void)handleDismissUnlimitedGroup:(int64_t)topicId {
  [self emitType:@"unlimitedGroupDismissed" data:@{ @"topicId" : @(topicId) }];
}

- (MIMCLaunchedResponse *)onLaunched:(NSString *)fromAccount
                         fromResource:(NSString *)fromResource
                               callId:(int64_t)callId
                           appContent:(NSData *)appContent {
  BOOL accepted = self.acceptIncomingRtsCalls;
  NSString *description = self.incomingRtsDescription ?: @"";
  [self emitType:@"rtsCallIncoming"
            data:@{
              @"callId" : @(callId),
              @"fromAccount" : fromAccount ?: @"",
              @"fromResource" : fromResource ?: @"",
              @"appContent" : [FlutterStandardTypedData
                  typedDataWithBytes:appContent ?: NSData.data],
              @"accepted" : @(accepted),
            }];
  return [[MIMCLaunchedResponse alloc] initWithAccepted:accepted
                                                   desc:description];
}

- (void)onAnswered:(int64_t)callId
           accepted:(BOOL)accepted
               desc:(NSString *)desc {
  [self emitType:@"rtsCallAnswered"
            data:@{
              @"callId" : @(callId),
              @"accepted" : @(accepted),
              @"description" : desc ?: @"",
            }];
}

- (void)onClosed:(int64_t)callId desc:(NSString *)desc {
  [self emitType:@"rtsCallClosed"
            data:@{
              @"callId" : @(callId),
              @"description" : desc ?: @"",
            }];
}

- (void)onData:(int64_t)callId
      fromAccount:(NSString *)fromAccount
         resource:(NSString *)resource
             data:(NSData *)data
         dataType:(RtsDataType)dataType
      channelType:(RtsChannelType)channelType {
  [self emitType:@"rtsData"
            data:@{
              @"callId" : @(callId),
              @"fromAccount" : fromAccount ?: @"",
              @"fromResource" : resource ?: @"",
              @"payload" : [FlutterStandardTypedData
                  typedDataWithBytes:data ?: NSData.data],
              @"dataType" : [self rtsDataTypeName:dataType],
              @"channelType" : [self rtsChannelTypeName:channelType],
            }];
}

- (void)onSendDataSuccess:(int64_t)callId
                    dataId:(int)dataId
                   context:(id)context {
  [self emitRtsSendResult:callId dataId:dataId success:YES context:context];
}

- (void)onSendDataFailure:(int64_t)callId
                    dataId:(int)dataId
                   context:(id)context {
  [self emitRtsSendResult:callId dataId:dataId success:NO context:context];
}

- (void)onCreateChannel:(int64_t)identity
                  callId:(int64_t)callId
                 callKey:(NSString *)callKey
                 success:(BOOL)success
                    desc:(NSString *)desc
                   extra:(NSData *)extra {
  if (success) [self setRtsChannel:callId active:YES];
  [self emitType:@"rtsChannelCreated"
            data:@{
              @"identity" : @(identity),
              @"callId" : @(callId),
              @"callKey" : callKey ?: @"",
              @"success" : @(success),
              @"description" : desc ?: @"",
              @"extra" : [FlutterStandardTypedData
                  typedDataWithBytes:extra ?: NSData.data],
            }];
}

- (void)onJoinChannel:(int64_t)callId
           appAccount:(NSString *)appAccount
             resource:(NSString *)resource
              success:(BOOL)success
                 desc:(NSString *)desc
                extra:(NSData *)extra
              members:(NSArray<MIMCChannelUser *> *)members {
  if (success) [self setRtsChannel:callId active:YES];
  NSMutableArray *mapped = [NSMutableArray arrayWithCapacity:members.count];
  for (MIMCChannelUser *member in members) {
    [mapped addObject:[self channelMemberMap:member]];
  }
  [self emitType:@"rtsChannelJoined"
            data:@{
              @"callId" : @(callId),
              @"appAccount" : appAccount ?: @"",
              @"resource" : resource ?: @"",
              @"success" : @(success),
              @"description" : desc ?: @"",
              @"extra" : [FlutterStandardTypedData
                  typedDataWithBytes:extra ?: NSData.data],
              @"members" : mapped,
            }];
}

- (void)onLeaveChannel:(int64_t)callId
            appAccount:(NSString *)appAccount
              resource:(NSString *)resource
               success:(BOOL)success
                  desc:(NSString *)desc {
  if (success) [self setRtsChannel:callId active:NO];
  [self emitType:@"rtsChannelLeft"
            data:@{
              @"callId" : @(callId),
              @"appAccount" : appAccount ?: @"",
              @"resource" : resource ?: @"",
              @"success" : @(success),
              @"description" : desc ?: @"",
            }];
}

- (void)onUserJoined:(int64_t)callId
           appAccount:(NSString *)appAccount
             resource:(NSString *)resource {
  [self emitType:@"rtsChannelUserJoined"
            data:@{
              @"callId" : @(callId),
              @"appAccount" : appAccount ?: @"",
              @"resource" : resource ?: @"",
            }];
}

- (void)onUserLeft:(int64_t)callId
         appAccount:(NSString *)appAccount
           resource:(NSString *)resource {
  [self emitType:@"rtsChannelUserLeft"
            data:@{
              @"callId" : @(callId),
              @"appAccount" : appAccount ?: @"",
              @"resource" : resource ?: @"",
            }];
}

- (void)onData:(int64_t)callId
      fromAccount:(NSString *)fromAccount
         resource:(NSString *)resource
             data:(NSData *)data
         dataType:(RtsDataType)dataType {
  [self emitType:@"rtsChannelData"
            data:@{
              @"callId" : @(callId),
              @"fromAccount" : fromAccount ?: @"",
              @"fromResource" : resource ?: @"",
              @"payload" : [FlutterStandardTypedData
                  typedDataWithBytes:data ?: NSData.data],
              @"dataType" : [self rtsDataTypeName:dataType],
            }];
}

- (void)emitRtsSendResult:(int64_t)callId
                    dataId:(int)dataId
                   success:(BOOL)success
                   context:(id)context {
  NSDictionary *sdkContext =
      [context isKindOfClass:NSDictionary.class] ? context : nil;
  BOOL isChannel = sdkContext != nil
                       ? [sdkContext[@"channel"] boolValue]
                       : [self isRtsChannel:callId];
  NSString *value = [sdkContext[@"value"] isKindOfClass:NSString.class]
                        ? sdkContext[@"value"]
                        : ([context isKindOfClass:NSString.class] ? context : @"");
  NSString *type = isChannel ? @"rtsChannelSendData" : @"rtsSendData";
  [self emitType:type
            data:@{
              @"callId" : @(callId),
              @"dataId" : @(dataId),
              @"success" : @(success),
              @"context" : value,
            }];
}

- (NSString *)rtsDataTypeName:(RtsDataType)dataType {
  return dataType == VIDEO ? @"video" : @"audio";
}

- (NSString *)rtsChannelTypeName:(RtsChannelType)channelType {
  switch (channelType) {
    case RELAY:
      return @"relay";
    case P2P_INTERNET:
      return @"p2pInternet";
    case P2P_INTRANET:
      return @"p2pIntranet";
  }
  return @"automatic";
}

- (void)complete:(FlutterResult)result
        operation:(NSString *)operation
             code:(int)code
      description:(NSString *)description
            value:(id)value {
  if (result == nil) return;
  [self runOnMain:^{
    if (code == 0) {
      result(value);
    } else {
      result([FlutterError errorWithCode:[NSString stringWithFormat:@"%@_%d", operation, code]
                                  message:description
                                  details:nil]);
    }
  }];
}

#pragma mark - FlutterStreamHandler

- (FlutterError *)onListenWithArguments:(id)arguments
                               eventSink:(FlutterEventSink)events {
  self.eventSink = events;
  return nil;
}

- (FlutterError *)onCancelWithArguments:(id)arguments {
  self.eventSink = nil;
  return nil;
}

- (void)dealloc {
  [self disposeUser];
}

@end
